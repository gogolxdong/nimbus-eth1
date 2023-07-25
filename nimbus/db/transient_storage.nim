import tables, stint, eth/common, chronicles, strformat

type
  StorageTable = ref object
    map*: Table[UInt256, UInt256]

  TransientStorage* = object
    map*: Table[EthAddress, StorageTable]

#######################################################################
# Private helpers
#######################################################################
proc `$`*(storageRef: StorageTable):string = 
  for slot, value in storageRef.map:
    result.add &"slot: {slot} value: {value}\n"

proc merge(a, b: StorageTable) =
  for k, v in b.map:
    a.map[k] = v

#######################################################################
# Public functions
#######################################################################

proc init*(ac: var TransientStorage) =
  ac.map = initTable[EthAddress, StorageTable]()

proc init*(_: type TransientStorage): TransientStorage {.inline.} =
  result.init()

func getStorage*(ac: TransientStorage,
                 address: EthAddress, slot: UInt256): (bool, UInt256) =
  var table = ac.map.getOrDefault(address)
  if table.isNil:
    return (false, 0.u256)

  table.map.withValue(slot, val):
    return (true, val[])
  do:
    return (false, 0.u256)

proc setStorage*(ac: var TransientStorage, address: EthAddress, slot, value: UInt256) =
  info "setStorage", address=address, slot=slot, value=value
  var table = ac.map.getOrDefault(address)
  if table.isNil:
    table = StorageTable()
    ac.map[address] = table

  table.map[slot] = value

proc merge*(ac: var TransientStorage, other: TransientStorage) =
  for k, v in other.map:
    ac.map.withValue(k, val):
      val[].merge(v)
    do:
      ac.map[k] = v

proc clear*(ac: var TransientStorage) {.inline.} =
  ac.map.clear()
