{.used, push raises: [].}

import
  eth/p2p,
  ../../core/[chain, tx_pool], ../../evm/async/data_sources,
  ../protocol,
  ./eth as handlers_eth,
  ./snap as handlers_snap

# ------------------------------------------------------------------------------
# Public functions: convenience mappings for `eth`
# ------------------------------------------------------------------------------

proc setEthHandlerNewBlocksAndHashes*(node: var EthereumNode; blockHandler: NewBlockHandler; hashesHandler: NewBlockHashesHandler; arg: pointer; ) {.gcsafe, raises: [CatchableError].} =
  let w = EthWireRef(node.protocolState protocol.eth)
  w.setNewBlockHandler(blockHandler, arg)
  w.setNewBlockHashesHandler(hashesHandler, arg)

proc addEthHandlerCapability*(node: var EthereumNode;peerPool: PeerPool;chain: ChainRef;txPool = TxPoolRef(nil); asyncDataSource = AsyncDataSource(nil)) =
  node.addCapability(protocol.eth, EthWireRef.new(chain, txPool, peerPool, asyncDataSource))

# ------------------------------------------------------------------------------
# Public functions: convenience mappings for `snap`
# ------------------------------------------------------------------------------

proc addSnapHandlerCapability*(
    node: var EthereumNode;
    peerPool: PeerPool;
    chain = ChainRef(nil);
      ) =
  ## Install `snap` handlers,Passing `chein` as `nil` installs the handler
  ## in minimal/outbound mode.
  if chain.isNil:
    node.addCapability protocol.snap
  else:
    node.addCapability(protocol.snap, SnapWireRef.init(chain, peerPool))

# ------------------------------------------------------------------------------
# End
# ------------------------------------------------------------------------------
