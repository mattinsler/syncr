Manifest = exports.Manifest = require './manifest'
exports.compute_delta = Manifest.compute_delta

exports.create_manifest = (root, opts, cb) ->
  if typeof opts is 'function'
    cb = opts
    opts = {}
  
  new Manifest(root, opts).create(cb)
