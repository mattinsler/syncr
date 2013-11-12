async = require 'async'
syncr = require '../lib/syncr'

# syncr.create_manifest './', (err, manifest) ->
#   return console.log(err.stack) if err?
#   console.log manifest

async.parallel
  lhs: (cb) -> syncr.create_manifest('./', ignore: 'manifestignore', cb)
  rhs: (cb) -> syncr.create_manifest('./', ignore: 'foobar.coffee', cb)
  # rhs: (cb) -> syncr.create_manifest('./', cb)
, (err, data) ->
  console.log data.lhs
  console.log data.rhs
  console.log syncr.compute_delta(data.lhs, data.rhs)
  
# lhs =
#   created_at: new Date()
#   hash: '91df06a2bfe55898f55212cd4af8874a63c3bfc9'
#   files:
#     'foobar.coffee': '41e1d265c9d8e399a7deeb2d6383f82f68087bad'
#     'test-manifest.coffee': 'a61b64058880f651e37b3776b0f28fc162e08a86'
# 
# rhs =
#   created_at: new Date()
#   hash: '01df06a2bfe55898f55212cd4af8874a63c3bfc9'
#   files:
#     'foobar.coffee': '51e1d265c9d8e399a7deeb2d6383f82f68087bad'
#     'new-manifest': 'a61b64058880f651e37b3776b0f28fc162e08a86'
# 
# console.log syncr.compute_delta(lhs, rhs)
