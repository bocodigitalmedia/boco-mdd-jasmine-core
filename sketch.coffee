MarkdownDriven = require 'boco-markdown-driven'
Core = require './source'

class CoffeeToken
  type: null
  value: null
  variable: null
  firstLine: null
  firstColumn: null
  lastLine: null
  lastColumn: null

  constructor: (props = {}) ->
    @[key] = val for own key, val of props

  @isVariable: (token) ->
    token.type is "IDENTIFIER" and token.variable

  @getValue: (token) ->
    token.value

  @convert: (csToken) ->
    [type, value, {first_line, first_column, last_line, last_column}] = csToken
    new CoffeeToken
      type: type, value: value, variable: csToken.variable,
      firstLine: first_line, firstColumn: first_column,
      lastLine: last_line, lastColumn: last_column

class CoffeeScriptService extends Core.ScriptService
  tokenize: (code) ->
    require("coffee-script").tokens(code).map CoffeeToken.convert

  getVariableNames: (code) ->
    tokens = @tokenize(code).filter CoffeeToken.isVariable
    names = tokens.map CoffeeToken.getValue
    reduceUnique = (vals, val) -> vals.push(val) unless val in vals; vals
    names.reduce reduceUnique, []

lexer = MarkdownDriven.configuration.lexer

parser = new MarkdownDriven.Parser
  nativeLanguages: ["coffee", "coffeescript", "coffee-script"]

generator = new Core.Generator scriptService: new CoffeeScriptService

markdown = require("fs").readFileSync("example.md").toString()
tokens = lexer.lex markdown
parseTree = parser.parse tokens
snippets = generator.generateSnippets parseTree
console.log JSON.stringify(snippets, null, 2)
