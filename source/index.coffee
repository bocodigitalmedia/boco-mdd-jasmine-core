configure = ($ = {}) ->

  $.indentationString ?= "  "
  $.joinString ?= "\n"
  $.globalVariables ?= require "./globalVariables"
  $.filesVariableName ?= "$files"
  $.doneFunctionName ?= "ok"

  class Snippets
    snippets: null

    constructor: (props = {}) ->
      @[key] = val for own key, val of props
      @snippets ?= []

    add: (snippet) ->
      @snippets.push snippet

    addBreak: ->
      @add type: "Break"

    addInitializeFilesVariable: ({variableName}) ->
      @add type: "InitializeFilesVariable", variableName: variableName

    addDescribeStart: ({text, depth}) ->
      @add type: "DescribeStart", text: text, depth: depth

    addInitializeVariables: ({variableNames, depth}) ->
      @add type: "InitializeVariables", variableNames: variableNames, depth: depth

    addBeforeEachStart: ({depth}) ->
      @add type: "BeforeEachStart", depth: depth

    addAssignFile: ({variableName, path, data, depth}) ->
      @add type: "AssignFile", variableName: variableName, path: path, data: data, depth: depth

    addBeforeEachCode: ({code, depth}) ->
      @add type: "BeforeEachCode", code: code, depth: depth

    addBeforeEachEnd: ({depth}) ->
      @add type: "BeforeEachEnd", depth: depth

    addAfterEachStart: ({depth}) ->
      @add type: "AfterEachStart", depth: depth

    addDeleteFile: ({variableName, path, depth}) ->
      @add type: "DeleteFile", variableName: variableName, path: path, depth: depth

    addAfterEachEnd: ({depth}) ->
      @add type: "AfterEachEnd", depth: depth

    addAssertionStart: ({doneFunctionName, text, isAsync, depth}) ->
      @add type: "AssertionStart", doneFunctionName: doneFunctionName, text: text, isAsync: isAsync, depth: depth

    addAssertionCode: ({code, depth}) ->
      @add type: "AssertionCode", code: code, depth: depth

    addAssertionEnd: ({depth}) ->
      @add type: "AssertionEnd", depth: depth

    addDescribeEnd: ({depth}) ->
      @add type: "DescribeEnd", depth: depth

    addBreak: ->
      @add type: "Break", depth: 0

    toArray: ->
      @snippets.slice()

  class SnippetsRenderer
    indentationString: null
    joinString: null

    constructor: (props = {}) ->
      @indentationString ?= $.indentationString
      @joinString ?= $.joinString

    indent: (code, depth) ->
      indentation = [0...depth].map(=> @indentationString).join('')
      code.replace /^/gm, indentation

    renderSnippet: (renderedSnippets, snippet) ->
      return renderedSnippets.concat("") if snippet.type is "Break"

      renderFnName = "render#{snippet.type}"
      renderFn = @[renderFnName]
      throw Error("#{renderFnName} not defined") unless renderFn?

      snippetStr = renderFn.call @, snippet
      return renderedSnippets unless snippetStr?

      renderedSnippet = @indent snippetStr, snippet.depth
      renderedSnippets.push renderedSnippet
      renderedSnippets

    render: (snippets) ->
      renderedSnippets = snippets.toArray().reduce @renderSnippet.bind(@), []
      renderedSnippets.join(@joinString) + "\n"

  class ScriptService
    globalVariables: null

    constructor: (props = {}) ->
      @[key] = val for own key, val of props
      @globalVariables ?= $.globalVariables

    isGlobalVariable: (v) ->
      v in @globalVariables

    getVariableNames: (code) ->
      throw Error("not implemented")

  class Generator
    scriptService: null
    snippetsRenderer: null
    filesVariableName: null
    doneFunctionName: null

    constructor: (props = {}) ->
      @[key] = val for own key, val of props
      @filesVariableName ?= $.filesVariableName
      @doneFunctionName ?= $.doneFunctionName

    getContextVariableNames: (contextNode) ->
      beforeEachNodes = contextNode.getBeforeEachNodes()
      code = beforeEachNodes.map(({code}) -> code).join("\n")
      vars = @scriptService.getVariableNames code

      if (ancestorContexts = contextNode.getAncestorContexts())?
        reduceAncestorVars = (vars, ancestorContext) => vars.concat @getContextVariableNames(ancestorContext)
        ancestorVars = ancestorContexts.reduce reduceAncestorVars, []
        vars = vars.filter (v) -> ancestorVars.indexOf(v) is -1

      vars.filter (v) => !@scriptService.isGlobalVariable(v)

    isAsyncAssertion: (code) ->
      ///\b#{@doneFunctionName}\(\)///.test code

    generateBeforeEach: (snippets, contextNode) ->
      beforeEachNodes = contextNode.getBeforeEachNodes()
      fileNodes = contextNode.getFileNodes()
      return snippets unless beforeEachNodes.length or fileNodes.length

      depth = contextNode.depth + 1

      snippets.addBreak()
      snippets.addBeforeEachStart depth: depth

      fileNodes.forEach ({path, data, depth}) =>
        snippets.addAssignFile
          variableName: @filesVariableName
          path: path
          data: data
          depth: depth + 1

      snippets.addBreak() if fileNodes.length

      beforeEachNodes.forEach ({code, depth}) ->
        snippets.addBeforeEachCode
          code: code
          depth: depth + 1

      snippets.addBeforeEachEnd depth: depth
      snippets

    generateAfterEach: (snippets, contextNode) ->
      fileNodes = contextNode.getFileNodes()
      return snippets unless fileNodes.length

      depth = contextNode.depth + 1

      snippets.addBreak()
      snippets.addAfterEachStart depth: depth

      fileNodes.forEach ({path, depth}) =>
        snippets.addDeleteFile
          variableName: @filesVariableName
          path: path
          depth: depth + 1

      snippets.addBeforeEachEnd depth: depth
      snippets

    generateAssertion: (snippets, assertionNode) ->
      {depth, text, code} = assertionNode

      snippets.addBreak()
      snippets.addAssertionStart
        text: text
        isAsync: @isAsyncAssertion(code)
        doneFunctionName: @doneFunctionName
        depth: depth

      snippets.addAssertionCode code: code, depth: depth + 1
      snippets.addAssertionEnd depth: depth
      snippets

    generateAssertions: (snippets, assertionNodes) ->
      return snippets unless assertionNodes.length
      assertionNodes.reduce @generateAssertion.bind(@), snippets

    generateDescribe: (snippets, contextNode) ->
      {depth, text} = contextNode
      variableNames = @getContextVariableNames contextNode

      snippets.addBreak()
      snippets.addDescribeStart text: text, depth: depth

      if !!(variableNames.length)
        snippets.addInitializeVariables variableNames: variableNames, depth: depth + 1

      snippets = @generateBeforeEach snippets, contextNode
      snippets = @generateAfterEach snippets, contextNode
      snippets = @generateAssertions snippets, contextNode.getAssertionNodes()
      snippets = @generateDescribes snippets, contextNode.getContextNodes()

      snippets.addDescribeEnd depth: depth
      snippets

    generateDescribes: (snippets, contextNodes) ->
      return snippets unless contextNodes.length
      contextNodes.reduce @generateDescribe.bind(@), snippets

    generateSnippets: (parseTree, snippets = (new Snippets)) ->
      snippets.addInitializeFilesVariable variableName: @filesVariableName, depth: parseTree.depth + 1
      snippets = @generateDescribes snippets, parseTree.getContextNodes()

    generate: (parseTree) ->
      snippets = @generateSnippets parseTree
      @snippetsRenderer.render snippets

  MarkdownDrivenJasmineCore =
    configuration: $
    configure: configure
    Snippets: Snippets
    SnippetsRenderer: SnippetsRenderer
    ScriptService: ScriptService
    Generator: Generator

module.exports = configure()
