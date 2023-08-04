import strutils, eth/db/kvstore

export kvstore

type DbBackend* = enum
  none,
  sqlite,
  rocksdb,
  memoryDB

const
  nimbus_db_backend* {.strdefine.} = "rocksdb"
  dbBackend* = parseEnum[DbBackend](nimbus_db_backend)

when dbBackend == sqlite:
  import eth/db/kvstore_sqlite3 as database_backend
elif dbBackend == rocksdb:
  import ./kvstore_rocksdb as database_backend

type
  ChainDB* = ref object of RootObj
    kv*: KvStoreRef
    when dbBackend == rocksdb:
      rdb*: RocksStoreRef

# TODO KvStore is a virtual interface and TrieDB is a virtual interface - one
#      will be enough eventually - unless the TrieDB interface gains operations
#      that are not typical to KvStores
proc get*(db: ChainDB, key: openArray[byte]): seq[byte] =
  var res: seq[byte]
  proc onData(data: openArray[byte]) = res = @data
  if db.kv.get(key, onData).expect("working database"):
    return res

proc put*(db: ChainDB, key, value: openArray[byte]) =
  db.kv.put(key, value).expect("working database")

proc contains*(db: ChainDB, key: openArray[byte]): bool =
  db.kv.contains(key).expect("working database")

proc del*(db: ChainDB, key: openArray[byte]): bool =
  db.kv.del(key).expect("working database")

when dbBackend == sqlite:
  proc newChainDB*(path: string): ChainDB =
    let db = SqStoreRef.init(path, "nimbus").expect("working database")
    ChainDB(kv: kvStore db.openKvStore().expect("working database"))
elif dbBackend == rocksdb:
  proc newChainDB*(path: string): ChainDB =
    let rdb = RocksStoreRef.init(path, "nimbus").tryGet()
    ChainDB(kv: kvStore rdb, rdb: rdb)

elif dbBackend == none:
  discard

when dbBackend != none:
  export database_backend
