import eth/db/kvstore
import os, strutils, sequtils, tables
import chronicles

type
  MemoryStoreRef* = ref object of RootObj
    store*: TableRef[openArray[byte], seq[byte]]

proc get*(db: MemoryStoreRef, key: openArray[byte], onData: kvstore.DataProc): KvResult[bool] =
    var value = db.store.getOrDefault key
    onData(value)
    ok(true)

proc find*(db: MemoryStoreRef, prefix: openArray[byte], onFind: kvstore.KeyValueProc): KvResult[void] =
    onFind(prefix, db.store.getOrDefault prefix)
    ok()

proc put*(db: MemoryStoreRef, key, value: openArray[byte]): KvResult[void] =
    db.store[key] = @value
    ok()

proc del*(db: MemoryStoreRef, key: openArray[byte]): KvResult[bool] =
    db.store.del(key)
    ok(true)

proc contains*(db: MemoryStoreRef, key: openArray[byte]): KvResult[bool] =
    if db.store.contains key:
        ok(true)
    else:
        ok(false)

proc clear*(db: MemoryStoreRef): KvResult[bool] =
    db.store.clear()
    ok(true)

proc close*(db: MemoryStoreRef) =
    # var env = newLMDBEnv(getCurrentDir() / ".lmdb")
    # var txn = env.newTxn()
    # let dbi = txn.dbiOpen("", 0)
    # for key, value in db.store:
    #     var keyVal = Val(mvSize: key.len.uint, mvData: key[0].unsafeAddr)
    #     var valueVal = Val(mvSize: value.len.uint, mvData: value[0].unsafeAddr)
    #     echo txn.put(dbi, keyVal.addr, valueVal.addr, 0)
    
    # txn.commit()
    db.store.clear()


proc init*(T: type MemoryStoreRef): KvResult[T] =
    ok(T(store: newTable[openArray[byte], seq[byte]]()))

