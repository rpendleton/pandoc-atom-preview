_ = require 'underscore-plus'
path = require 'path'
fs = require 'fs-plus'
process = require 'child_process'
cheerio = require 'cheerio'
{$} = require 'atom-space-pen-views'

{resourcePath} = atom.getLoadSettings()
packagePath = path.dirname(__dirname)

exports.toDOMFragment = (text='', filePath, grammar, callback) ->
  render text, filePath, (error, html) ->
    return callback(error) if error?

    iframe = document.createElement('iframe')
    iframe.src = "data:text/html;charset=UTF-8, #{encodeURIComponent html}"

    callback(null, iframe)

exports.toHTML = (text='', filePath, grammar, callback) ->
  render text, filePath, (error, html) ->
    return callback(error) if error?
    callback(null, html)

render = (text, filePath, callback) ->
  path_ = atom.config.get 'pandoc-preview.pandocPath'
  opts_ = atom.config.get 'pandoc-preview.pandocOpts'
  return unless path_? and opts_?

  options =
      cwd: path.dirname filePath

  pandoc=process.spawn(
    path_,
    opts_.split(' '),
    options
  )

  html = ""
  error = ""
  pandoc.stdout.on 'data', (data) -> html += data
  pandoc.stderr.on 'data', (data) -> error += data

  pandoc.stdin.write(text)
  pandoc.stdin.end()

  pandoc.on 'close', (code) ->
    if code != 0
      output = error.trim()

      error =
        display: '$ ' + path_ + ' ...\n  ' + output.split('\n').join('\n  ')
        output: output
        statusCode: code

      return callback(error)
    else
      html = resolveImagePaths(html, filePath)
      callback(null, html.trim())

resolveImagePaths = (html, filePath) ->
  o = cheerio.load(html)
  for imgElement in o('img')
    img = o(imgElement)
    if src = img.attr('src')
      continue if src.match(/^(https?|atom):\/\//)
      continue if src.startsWith(process.resourcesPath)
      continue if src.startsWith(resourcePath)
      continue if src.startsWith(packagePath)

      if src[0] is '/'
        unless fs.isFileSync(src)
          img.attr('src', atom.project.getDirectories()[0]?.resolve(src.substring(1)))
      else
        img.attr('src', path.resolve(path.dirname(filePath), src))

  o.html()
