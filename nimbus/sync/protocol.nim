when defined(legacy_eth66_enabled):
  import ./protocol/eth66 as proto_eth
  type eth* = eth66
else:
  import ./protocol/eth67 as proto_eth
  type eth* = eth67

import
  ./protocol/snap1 as proto_snap

export
  proto_eth,
  proto_snap

type
  snap* = snap1

  SnapAccountRange* = accountRangeObj
    ## Syntactic sugar, type defined in `snap1`

  SnapStorageRanges* = storageRangesObj
    ## Ditto

  SnapByteCodes* = byteCodesObj
    ## Ditto

  SnapTrieNodes* = trieNodesObj
    ## Ditto

# End
