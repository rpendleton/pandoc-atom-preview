url = require 'url'

PandocPreviewView = null # Defer until used
renderer = null # Defer until used

createPandocPreviewView = (state) ->
  PandocPreviewView ?= require './pandoc-preview-view'
  new PandocPreviewView(state)

isPandocPreviewView = (object) ->
  PandocPreviewView ?= require './pandoc-preview-view'
  object instanceof PandocPreviewView

atom.deserializers.add
  name: 'PandocPreviewView'
  deserialize: (state) ->
    createPandocPreviewView(state) if state.constructor is Object

module.exports =
  config:
    pandocPath:
      type: 'string'
      default: 'pandoc'
    pandocOpts:
      type: 'string'
      default: '-f markdown -t html5'
    liveUpdate:
      type: 'boolean'
      default: false
    openPreviewInSplitPane:
      type: 'boolean'
      default: true
    grammars:
      type: 'array'
      default: [
        'source.gfm'
        'source.litcoffee'
        'text.html.basic'
        'text.plain'
        'text.plain.null-grammar'
      ]

  activate: ->
    atom.commands.add 'atom-workspace',
      'pandoc-preview:toggle': =>
        @toggle()
      'pandoc-preview:copy-html': =>
        @copyHtml()

    previewFile = @previewFile.bind(this)
    atom.commands.add '.tree-view .file .name[data-name$=\\.markdown]', 'pandoc-preview:preview-file', previewFile
    atom.commands.add '.tree-view .file .name[data-name$=\\.md]', 'pandoc-preview:preview-file', previewFile
    atom.commands.add '.tree-view .file .name[data-name$=\\.mdown]', 'pandoc-preview:preview-file', previewFile
    atom.commands.add '.tree-view .file .name[data-name$=\\.mkd]', 'pandoc-preview:preview-file', previewFile
    atom.commands.add '.tree-view .file .name[data-name$=\\.mkdown]', 'pandoc-preview:preview-file', previewFile
    atom.commands.add '.tree-view .file .name[data-name$=\\.ron]', 'pandoc-preview:preview-file', previewFile
    atom.commands.add '.tree-view .file .name[data-name$=\\.txt]', 'pandoc-preview:preview-file', previewFile

    atom.workspace.addOpener (uriToOpen) ->
      try
        {protocol, host, pathname} = url.parse(uriToOpen)
      catch error
        return

      return unless protocol is 'pandoc-preview:'

      try
        pathname = decodeURI(pathname) if pathname
      catch error
        return

      if host is 'editor'
        createPandocPreviewView(editorId: pathname.substring(1))
      else
        createPandocPreviewView(filePath: pathname)

  toggle: ->
    if isPandocPreviewView(atom.workspace.getActivePaneItem())
      atom.workspace.destroyActivePaneItem()
      return

    editor = atom.workspace.getActiveTextEditor()
    return unless editor?

    grammars = atom.config.get('pandoc-preview.grammars') ? []
    return unless editor.getGrammar().scopeName in grammars

    @addPreviewForEditor(editor) unless @removePreviewForEditor(editor)

  uriForEditor: (editor) ->
    "pandoc-preview://editor/#{editor.id}"

  removePreviewForEditor: (editor) ->
    uri = @uriForEditor(editor)
    previewPane = atom.workspace.paneForURI(uri)
    if previewPane?
      previewPane.destroyItem(previewPane.itemForURI(uri))
      true
    else
      false

  addPreviewForEditor: (editor) ->
    uri = @uriForEditor(editor)
    previousActivePane = atom.workspace.getActivePane()
    options =
      searchAllPanes: true
    if atom.config.get('pandoc-preview.openPreviewInSplitPane')
      options.split = 'right'
    atom.workspace.open(uri, options).done (pandocPreviewView) ->
      if isPandocPreviewView(pandocPreviewView)
        previousActivePane.activate()

  previewFile: ({target}) ->
    filePath = target.dataset.path
    return unless filePath

    for editor in atom.workspace.getTextEditors() when editor.getPath() is filePath
      @addPreviewForEditor(editor)
      return

    atom.workspace.open "pandoc-preview://#{encodeURI(filePath)}", searchAllPanes: true

  copyHtml: ->
    editor = atom.workspace.getActiveTextEditor()
    return unless editor?

    renderer ?= require './renderer'
    text = editor.getSelectedText() or editor.getText()
    renderer.toHTML text, editor.getPath(), editor.getGrammar(), (error, html) =>
      if error
        console.warn('Copying Markdown as HTML failed', error)
      else
        atom.clipboard.write(html)
