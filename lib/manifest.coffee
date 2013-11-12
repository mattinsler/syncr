fs = require 'fs'
path = require 'path'
async = require 'async'
crypto = require 'crypto'
minimatch = require 'minimatch'

invert_obj = (obj) ->
  Object.keys(obj).reduce (o, k) ->
    o[obj[k]] = k
    o
  , {}

class Manifest
  constructor: (@root, @opts = {}) ->
    @root = path.resolve(@root)
    
    @opts.all ?= false
    @opts.absolute_path ?= false
    
    @opts.ignore = [@opts.ignore] if @opts.ignore? and typeof @opts.ignore is 'string'
    
    if @opts.ignore_file?
      try
        content = fs.readFileSync(@opts.ignore_file)
      catch err
        throw new Error('Could not read the manifest ignore file at ' + @opts.ignore_file)
      
      ignore = content.toString().split('\n').filter (line) ->
        line = line.trim()
        return false if line is ''
        return false if line[0] is '#'
        true
      
      @opts.ignore = (@opts.ignore or []).concat(ignore)
    
    if @opts.ignore?
      if Array.isArray(@opts.ignore)
        ignore = Array::slice.call(@opts.ignore)
        @opts.ignore = (filename) ->
          for pattern in ignore
            return true if minimatch(filename, pattern)
          false
    else
      @opts.ignore = -> false
  
  _filter: (file) ->
    # return false if file in ['.', '..']
    return false if @opts.all is false and file[0] is '.'
    return false if @opts.ignore(file)
    true
  
  _read_file: (file, callback) ->
    if @opts.absolute_path is false
      callback(null, file.slice(@root.length).replace(/^\/*/, ''))
    else
      callback(null, file)
  
  _read_dir: (dir, callback) ->
    fs.readdir dir, (err, files) =>
      return callback(err) if err?
      
      res = []
      files = files.filter(@_filter.bind(@)).map (f) -> path.join(dir, f)
      
      async.each files, (file, cb) =>
        fs.stat file, (err, stat) =>
          return cb(err) if err?
          
          if stat.isDirectory()
            @_read_dir file, (err, dir_files) ->
              return cb(err) if err?
              Array::push.apply(res, dir_files)
              cb()
          else
            @_read_file file, (err, f) ->
              return cb(err) if err?
              res.push(f)
              cb()
      , (err) ->
        return callback(err) if err?
        callback(null, res)
    
  create: (callback) ->
    manifest =
      created_at: new Date()
    
    manifest_hash = crypto.createHash('sha1')
    
    @_read_dir @root, (err, files) =>
      return callback(err) if err?
      
      files = files.sort()
      
      async.reduce files, {}, (memo, file, cb) =>
        hash = crypto.createHash('sha1')
        manifest_hash.update(file)
        
        stream = fs.createReadStream(path.join(@root, file))
        stream.on('error', cb)
        stream.on 'data', (data) ->
          hash.update(data)
          manifest_hash.update(data)
        stream.on 'end', (data) ->
          hash.update(data) if data?
          manifest_hash.update(data) if data?
          memo[file] = hash.digest('hex')
          cb(null, memo)
      , (err, files) ->
        return callback(err) if err?
        
        manifest.hash = manifest_hash.digest('hex')
        manifest.files = files
        
        callback(null, manifest)
  
  @hash_file: (file, callback) ->
    hash = crypto.createHash('sha1')
    stream = fs.createReadStream(file)
    stream.on('error', callback)
    stream.on 'data', (data) ->
      hash.update(data)
    stream.on 'end', (data) ->
      hash.update(data) if data?
      callback(null, hash.digest('hex'))
  
  @compute_delta: (from, to) ->
    res =
      add: []
      remove: []
      change: []
      rename: {}
    
    return res if from.hash is to.hash
    
    create_hash = (files) ->
      Object.keys(files)
      .map (f) ->
        [files[f], f].join(':')
      .reduce (o, k) ->
        o[k] = 1
        o
      , {}
    
    get_filename = (h) -> h.replace(/^[^:]+:/, '')
    
    fhash = create_hash(from.files)
    thash = create_hash(to.files)
    
    res.add = Object.keys(thash)
    .filter((h) -> !fhash[h]?)
    .map(get_filename)
    .sort()
    
    res.remove = Object.keys(fhash)
    .filter((h) -> !thash[h]?)
    .map(get_filename)
    .sort()
    
    a = r = 0
    while a < res.add.length and r < res.remove.length
      if res.add[a] < res.remove[r]
        if from.files[res.remove[r]] is to.files[res.add[a]]
          res.rename[res.remove[r]] = res.add[a]
          res.add.splice(a, 1)
          res.remove.splice(r, 1)
        else
          ++a
      else if res.add[a] > res.remove[r]
        if from.files[res.remove[r]] is to.files[res.add[a]]
          res.rename[res.remove[r]] = res.add[a]
          res.add.splice(a, 1)
          res.remove.splice(r, 1)
        else
          ++r
      else
        res.change.push(res.add[a])
        res.add.splice(a, 1)
        res.remove.splice(r, 1)
    
    res

module.exports = Manifest
