fs = require 'fs'
path = require 'path'
async = require 'async'
crypto = require 'crypto'
minimatch = require 'minimatch'

class Manifest
  constructor: (@root, @opts = {}) ->
    @opts.all ?= false
    
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
    return false if file in ['.', '..']
    return false if @opts.all is false and file[0] is '.'
    return false if @opts.ignore(file)
    true
  
  _read_file: (file, callback) ->
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
    
    @_read_dir @root, (err, files) ->
      return callback(err) if err?
      
      files = files.sort()
      manifest_hash = crypto.createHash('sha1')
      
      async.reduce files, {}, (memo, file, cb) ->
        hash = crypto.createHash('sha1')
        stream = fs.createReadStream(file)
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
  
  @compute_delta: (from, to) ->
    return true if from.hash is to.hash
    
    res =
      add: []
      remove: []
      change: []
    
    compare = (lhs, rhs) ->
      return -1 unless lhs?
      return 1 unless rhs?
      String::localeCompare.call(lhs, rhs)
    
    f = t = 0
    from_files = Object.keys(from.files).sort(compare)
    to_files = Object.keys(to.files).sort(compare)
    
    until f is from_files.length and t is to_files.length
      ffile = from_files[f]
      tfile = to_files[t]
      
      cmp = compare(ffile, tfile)
      if cmp < 0
        res.remove.push(ffile)
        ++f
      else if cmp > 0
        res.add.push(tfile)
        ++t
      else
        res.change.push(ffile) if from.files[ffile] isnt to.files[tfile]
        ++t
        ++f
    
    res

module.exports = Manifest
