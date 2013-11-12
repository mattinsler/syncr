(function() {
  var Manifest, async, crypto, fs, invert_obj, minimatch, path;

  fs = require('fs');

  path = require('path');

  async = require('async');

  crypto = require('crypto');

  minimatch = require('minimatch');

  invert_obj = function(obj) {
    return Object.keys(obj).reduce(function(o, k) {
      o[obj[k]] = k;
      return o;
    }, {});
  };

  Manifest = (function() {

    function Manifest(root, opts) {
      var content, ignore, _base, _base1, _ref, _ref1;
      this.root = root;
      this.opts = opts != null ? opts : {};
      this.root = path.resolve(this.root);
      if ((_ref = (_base = this.opts).all) == null) {
        _base.all = false;
      }
      if ((_ref1 = (_base1 = this.opts).absolute_path) == null) {
        _base1.absolute_path = false;
      }
      if ((this.opts.ignore != null) && typeof this.opts.ignore === 'string') {
        this.opts.ignore = [this.opts.ignore];
      }
      if (this.opts.ignore_file != null) {
        try {
          content = fs.readFileSync(this.opts.ignore_file);
        } catch (err) {
          throw new Error('Could not read the manifest ignore file at ' + this.opts.ignore_file);
        }
        ignore = content.toString().split('\n').filter(function(line) {
          line = line.trim();
          if (line === '') {
            return false;
          }
          if (line[0] === '#') {
            return false;
          }
          return true;
        });
        this.opts.ignore = (this.opts.ignore || []).concat(ignore);
      }
      if (this.opts.ignore != null) {
        if (Array.isArray(this.opts.ignore)) {
          ignore = Array.prototype.slice.call(this.opts.ignore);
          this.opts.ignore = function(filename) {
            var pattern, _i, _len;
            for (_i = 0, _len = ignore.length; _i < _len; _i++) {
              pattern = ignore[_i];
              if (minimatch(filename, pattern)) {
                return true;
              }
            }
            return false;
          };
        }
      } else {
        this.opts.ignore = function() {
          return false;
        };
      }
    }

    Manifest.prototype._filter = function(file) {
      if (this.opts.all === false && file[0] === '.') {
        return false;
      }
      if (this.opts.ignore(file)) {
        return false;
      }
      return true;
    };

    Manifest.prototype._read_file = function(file, callback) {
      if (this.opts.absolute_path === false) {
        return callback(null, file.slice(this.root.length).replace(/^\/*/, ''));
      } else {
        return callback(null, file);
      }
    };

    Manifest.prototype._read_dir = function(dir, callback) {
      var _this = this;
      return fs.readdir(dir, function(err, files) {
        var res;
        if (err != null) {
          return callback(err);
        }
        res = [];
        files = files.filter(_this._filter.bind(_this)).map(function(f) {
          return path.join(dir, f);
        });
        return async.each(files, function(file, cb) {
          return fs.stat(file, function(err, stat) {
            if (err != null) {
              return cb(err);
            }
            if (stat.isDirectory()) {
              return _this._read_dir(file, function(err, dir_files) {
                if (err != null) {
                  return cb(err);
                }
                Array.prototype.push.apply(res, dir_files);
                return cb();
              });
            } else {
              return _this._read_file(file, function(err, f) {
                if (err != null) {
                  return cb(err);
                }
                res.push(f);
                return cb();
              });
            }
          });
        }, function(err) {
          if (err != null) {
            return callback(err);
          }
          return callback(null, res);
        });
      });
    };

    Manifest.prototype.create = function(callback) {
      var manifest, manifest_hash,
        _this = this;
      manifest = {
        created_at: new Date()
      };
      manifest_hash = crypto.createHash('sha1');
      return this._read_dir(this.root, function(err, files) {
        if (err != null) {
          return callback(err);
        }
        files = files.sort();
        return async.reduce(files, {}, function(memo, file, cb) {
          var hash, stream;
          hash = crypto.createHash('sha1');
          manifest_hash.update(file);
          stream = fs.createReadStream(path.join(_this.root, file));
          stream.on('error', cb);
          stream.on('data', function(data) {
            hash.update(data);
            return manifest_hash.update(data);
          });
          return stream.on('end', function(data) {
            if (data != null) {
              hash.update(data);
            }
            if (data != null) {
              manifest_hash.update(data);
            }
            memo[file] = hash.digest('hex');
            return cb(null, memo);
          });
        }, function(err, files) {
          if (err != null) {
            return callback(err);
          }
          manifest.hash = manifest_hash.digest('hex');
          manifest.files = files;
          return callback(null, manifest);
        });
      });
    };

    Manifest.hash_file = function(file, callback) {
      var hash, stream;
      hash = crypto.createHash('sha1');
      stream = fs.createReadStream(file);
      stream.on('error', callback);
      stream.on('data', function(data) {
        return hash.update(data);
      });
      return stream.on('end', function(data) {
        if (data != null) {
          hash.update(data);
        }
        return callback(null, hash.digest('hex'));
      });
    };

    Manifest.compute_delta = function(from, to) {
      var a, create_hash, fhash, get_filename, r, res, thash;
      res = {
        add: [],
        remove: [],
        change: [],
        rename: {}
      };
      if (from.hash === to.hash) {
        return res;
      }
      create_hash = function(files) {
        return Object.keys(files).map(function(f) {
          return [files[f], f].join(':');
        }).reduce(function(o, k) {
          o[k] = 1;
          return o;
        }, {});
      };
      get_filename = function(h) {
        return h.replace(/^[^:]+:/, '');
      };
      fhash = create_hash(from.files);
      thash = create_hash(to.files);
      res.add = Object.keys(thash).filter(function(h) {
        return !(fhash[h] != null);
      }).map(get_filename).sort();
      res.remove = Object.keys(fhash).filter(function(h) {
        return !(thash[h] != null);
      }).map(get_filename).sort();
      a = r = 0;
      while (a < res.add.length && r < res.remove.length) {
        if (res.add[a] < res.remove[r]) {
          if (from.files[res.remove[r]] === to.files[res.add[a]]) {
            res.rename[res.remove[r]] = res.add[a];
            res.add.splice(a, 1);
            res.remove.splice(r, 1);
          } else {
            ++a;
          }
        } else if (res.add[a] > res.remove[r]) {
          if (from.files[res.remove[r]] === to.files[res.add[a]]) {
            res.rename[res.remove[r]] = res.add[a];
            res.add.splice(a, 1);
            res.remove.splice(r, 1);
          } else {
            ++r;
          }
        } else {
          res.change.push(res.add[a]);
          res.add.splice(a, 1);
          res.remove.splice(r, 1);
        }
      }
      return res;
    };

    return Manifest;

  })();

  module.exports = Manifest;

}).call(this);
