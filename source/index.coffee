configure = ($ = {}) ->

  $.indentationString ?= "  "
  $.joinString ?= "\n"
  $.reduceUnique ?= (arr, v) -> arr.push(v) if arr.indexOf(v) is -1; arr
  $.globalVariables ?= require("./global-variables")
  $.filesVariableName ?= "$files"
  $.doneFunctionName ?= "ok"
  $.scriptService ?= null

  class Snippets
    snippets: null

    constructor: (props = {}) ->
      @[key] = val for own key, val of props
      @snippets ?= []

    add: (snippet) ->
      @add snippet

    addDescribeStart: ({text, depth}) ->
      @add type: "DescribeStart", text: text, depth: depth

    addInitializeVariables: ({vars, depth}) ->
      @add type: "InitializeVariables", vars: vars, depth: depth

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

    map: (args...) ->
      @snippets.map args...

  class SnippetsRenderer
    indentationString: null
    joinString: null

    constructor: (props = {}) ->
      @indentationString ?= $.indentationString
      @joinString ?= $.joinString

    indent: (code, depth) ->
      indentation = [1...depth].map(=> @indentationString).join('')
      code.replace /^/gm, indentation

    renderSnippet: (snippet) ->
      snippetStr = @["render#{snippet.type}"].call this, snippet
      @indent snippetStr, snippet.depth

    render: (snippets) ->
      snippets.map(@renderSnippet.bind(@)).join(@joinString) + "\n"

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
    filesVariableName: null
    doneFunctionName: null
    snippetsRenderer: null

    constructor: (props = {}) ->
      @[key] = val for own key, val of props
      @scriptService ?= $.scriptService
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

      snippets.addBeforeEachStart depth: depth

      fileNodes.forEach ({path, data, depth}) =>
        snippets.addAssignFile
          variableName: @filesVariableName
          path: path
          data: data
          depth: depth + 1

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
      # ignore empty contexts
      return snippets unless contextNode.getAssertionNodes().length

      {depth, text} = contextNode
      variableNames = @getContextVariableNames contextNode

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
      snippets.addInitializeFilesVariable filesVariableName: @filesVariableName, depth: parseTree.depth + 1
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
