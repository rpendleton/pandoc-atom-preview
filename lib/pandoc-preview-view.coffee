_ = require 'underscore-plus'
path = require 'path'
fs = require 'fs-plus'
{File} = require 'pathwatcher'
{Emitter, Disposable, CompositeDisposable} = require 'atom'
{$, $$$, ScrollView} = require 'atom-space-pen-views'

renderer = require './renderer'

module.exports =
class PandocPreviewView extends ScrollView
  @content: ->
    @div class: 'pandoc-preview native-key-bindings', tabindex: -1

  constructor: ({@editorId, @filePath}) ->
    super
    @emitter = new Emitter
    @disposables = new CompositeDisposable

  attached: ->
    return if @isAttached
    @isAttached = true

    if @editorId?
      @resolveEditor(@editorId)
    else
      if atom.workspace?
        @subscribeToFilePath(@filePath)
      else
        @disposables.add atom.packages.onDidActivateInitialPackages =>
          @subscribeToFilePath(@filePath)

  serialize: ->
    deserializer: 'PandocPreviewView'
    filePath: @getPath()
    editorId: @editorId

  destroy: ->
    @disposables.dispose()

  onDidChangeTitle: (callback) ->
    @emitter.on 'did-change-title', callback

  onDidChangeModified: (callback) ->
    # No op to suppress deprecation warning
    new Disposable

  onDidChangeMarkdown: (callback) ->
    @emitter.on 'did-change-markdown', callback

  subscribeToFilePath: (filePath) ->
    @file = new File(filePath)
    @emitter.emit 'did-change-title'
    @handleEvents()
    @renderMarkdown()

  resolveEditor: (editorId) ->
    resolve = =>
      @editor = @editorForId(editorId)

      if @editor?
        @emitter.emit 'did-change-title' if @editor?
        @handleEvents()
        @renderMarkdown()
      else
        # The editor this preview was created for has been closed so close
        # this preview since a preview cannot be rendered without an editor
        @parents('.pane').view()?.destroyItem(this)

    if atom.workspace?
      resolve()
    else
      @disposables.add atom.packages.onDidActivateInitialPackages(resolve)

  editorForId: (editorId) ->
    for editor in atom.workspace.getTextEditors()
      return editor if editor.id?.toString() is editorId.toString()
    null

  handleEvents: ->
    @disposables.add atom.grammars.onDidAddGrammar => _.debounce((=> @renderMarkdown()), 250)
    @disposables.add atom.grammars.onDidUpdateGrammar _.debounce((=> @renderMarkdown()), 250)

    atom.commands.add @element,
      'core:move-up': =>
        @scrollUp()
      'core:move-down': =>
        @scrollDown()
      'core:save-as': (event) =>
        event.stopPropagation()
        @saveAs()
      'core:copy': (event) =>
        event.stopPropagation() if @copyToClipboard()
      'pandoc-preview:zoom-in': =>
        zoomLevel = parseFloat(@css('zoom')) or 1
        @css('zoom', zoomLevel + .1)
      'pandoc-preview:zoom-out': =>
        zoomLevel = parseFloat(@css('zoom')) or 1
        @css('zoom', zoomLevel - .1)
      'pandoc-preview:reset-zoom': =>
        @css('zoom', 1)

    changeHandler = =>
      @renderMarkdown()

      # TODO: Remove paneForURI call when ::paneForItem is released
      pane = atom.workspace.paneForItem?(this) ? atom.workspace.paneForURI(@getURI())
      if pane? and pane isnt atom.workspace.getActivePane()
        pane.activateItem(this)

    if @file?
      @disposables.add @file.onDidChange(changeHandler)
    else if @editor?
      @disposables.add @editor.getBuffer().onDidStopChanging =>
        changeHandler() if atom.config.get 'pandoc-preview.liveUpdate'
      @disposables.add @editor.onDidChangePath => @emitter.emit 'did-change-title'
      @disposables.add @editor.getBuffer().onDidSave =>
        changeHandler() unless atom.config.get 'pandoc-preview.liveUpdate'
      @disposables.add @editor.getBuffer().onDidReload =>
        changeHandler() unless atom.config.get 'pandoc-preview.liveUpdate'

  renderMarkdown: ->
    @showLoading()
    @getMarkdownSource().then (source) => @renderMarkdownText(source) if source?

  getMarkdownSource: ->
    if @file?
      @file.read()
    else if @editor?
      Promise.resolve(@editor.getText())
    else
      Promise.resolve(null)

  pageReady: (domFragment) ->
    @loading = false
    @emitter.emit 'did-change-markdown'
    @originalTrigger('pandoc-preview:markdown-changed')

    if old = @find('iframe.loaded')[0]
      domFragment.contentWindow.scrollTo(0, old.contentWindow.scrollY)

    @find(':not(.loading)').remove()
    domFragment.className = 'loaded'

  renderMarkdownText: (text) ->
    renderer.toDOMFragment text, @getPath(), @getGrammar(), (error, domFragment) =>
      if error
        @showError(error)
      else
        self = this
        domFragment.className = 'loading'
        @append(domFragment)
        domFragment.addEventListener 'load', (e) ->
          if e.target.contentWindow.MathJax?.version
            e.target.contentWindow.MathJax.Hub.Queue ->
              self.pageReady(domFragment)
          else
            self.pageReady(domFragment)

  getTitle: ->
    if @file?
      "#{path.basename(@getPath())} Preview"
    else if @editor?
      "#{@editor.getTitle()} Preview"
    else
      "Document Preview"

  getIconName: ->
    "markdown"

  getURI: ->
    if @file?
      "pandoc-preview://#{@getPath()}"
    else
      "pandoc-preview://editor/#{@editorId}"

  getPath: ->
    if @file?
      @file.getPath()
    else if @editor?
      @editor.getPath()

  getGrammar: ->
    @editor?.getGrammar()

  showError: (result) ->
    failureMessage = result?.display

    @html $$$ ->
      @h2 'Previewing Markdown Failed'
      @pre class: 'error', failureMessage if failureMessage?

  showLoading: ->
    @loading = true
    @append $$$ ->
      @div class: 'loader', =>
        @div class: 'markdown-spinner', 'Generating Document\u2026'

  copyToClipboard: ->
    return false if @loading

    selection = window.getSelection()
    selectedText = selection.toString()
    selectedNode = selection.baseNode

    # Use default copy event handler if there is selected text inside this view
    return false if selectedText and selectedNode? and (@[0] is selectedNode or $.contains(@[0], selectedNode))

    @getMarkdownSource().then (source) =>
      return unless source?

      renderer.toHTML source, @getPath(), @getGrammar(), (error, html) =>
        if error?
          console.warn('Copying Markdown as HTML failed', error)
        else
          atom.clipboard.write(html)

    true

  saveAs: ->
    return if @loading

    filePath = @getPath()
    if filePath
      filePath += '.html'
    else
      filePath = 'untitled.md.html'
      if projectPath = atom.project.getPath()
        filePath = path.join(projectPath, filePath)

    @getMarkdownSource().then (source) =>
      return unless source?

      renderer.toHTML source, @getPath(), @getGrammar(), (error, html) =>
        if error?
          console.warn('Copying Markdown as HTML failed', error)
        else
          if htmlFilePath = atom.showSaveDialogSync(filePath)
            fs.writeFileSync(htmlFilePath, html)
            atom.workspace.open(htmlFilePath)

  isEqual: (other) ->
    @[0] is other?[0] # Compare DOM elements
