import lmdb
import rocksdb
import eth/db/kvstore
import os, strutils, sequtils
import chronicles

type
  LMDBStoreRef* = ref object of RootObj
    store*: LMDBEnv

proc get*(db: LMDBStoreRef, key: openArray[byte], onData: kvstore.DataProc): KvResult[bool] =
    let txn = db.store.newTxn()
    let dbi = txn.dbiOpen("", 0)
    var keyVal = Val(mvSize: key.len.uint, mvData: key[0].unsafeAddr)
    var dataVal:Val
    var ret = txn.get(dbi, keyVal.addr, dataVal.addr)
    if ret == 0:
        var data = cast[ptr UncheckedArray[byte]](dataVal.mvData)
        onData(data.toOpenArray(0, dataVal.mvSize.int - 1))
        txn.abort()
    ok(true)

proc find*(db: LMDBStoreRef, prefix: openArray[byte], onFind: kvstore.KeyValueProc): KvResult[void] =
    raiseAssert "Unimplemented"

proc put*(db: LMDBStoreRef, key, value: openArray[byte]): KvResult[void] =
    info "put", key=key
    var keyVal = Val(mvSize: key.len.uint, mvData: key[0].unsafeAddr)
    var valueVal = Val(mvSize: value.len.uint, mvData: value[0].unsafeAddr)
    let txn = db.store.newTxn()
    let dbi = txn.dbiOpen("", 0)
    var ret = txn.put(dbi, addr keyVal, addr valueVal, 0.cuint)
    if ret == 0:
        txn.commit()
        db.store.close(dbi)
    ok()

proc del*(db: LMDBStoreRef, key: openArray[byte]): KvResult[bool] =
    let txn = db.store.newTxn()
    let dbi = txn.dbiOpen("", 0)
    var data = txn.get(dbi, $key)
    txn.del(dbi, $key, data)
    txn.commit()
    db.store.close(dbi)
    ok(true)

proc contains*(db: LMDBStoreRef, key: openArray[byte]): KvResult[bool] =
    echo "contains:", key
    let txn = db.store.newTxn()
    let dbi = txn.dbiOpen("", 0)
    var data = txn.get(dbi, $key)
    txn.abort()
    if data.len > 0:
        ok(true)
    else:
        ok(false)

proc clear*(db: LMDBStoreRef): KvResult[bool] =
    let txn = db.store.newTxn()
    let dbi = txn.dbiOpen("", 0)
    txn.emptyDb(dbi)
    db.store.envClose()
    txn.commit()
    ok(true)

proc close*(db: LMDBStoreRef) =
    let txn = db.store.newTxn()
    let dbi = txn.dbiOpen("", 0)
    txn.deleteAndCloseDb(dbi)
    txn.commit()


proc init*(T: type LMDBStoreRef, path:string): KvResult[T] =
    var store = newLMDBEnv(getCurrentDir() / ".lmdb")
    ok(T(store: store))