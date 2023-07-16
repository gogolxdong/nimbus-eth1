{.push raises: [].}

import
  std/[sets, options, random, hashes],
  eth/[p2p],
  "."/[protocol, types, sync_desc],
  eth/p2p/[private/p2p_types, peer_pool],
  chronicles,
  stew/[interval_set]

logScope:
  topics = "stateless-sync"

type
  HashToTime = TableRef[Hash256, Time]

  BlockchainSyncDefect* = object of Defect
    ## Catch and relay exception

  WantedBlocksState = enum
    Initial,
    Requested,
    Received,
    Persisted

  WantedBlocks = object
    isHash: bool
    hash: Hash256
    startIndex: BlockNumber
    numBlocks: uint
    state: WantedBlocksState
    headers: seq[BlockHeader]
    bodies: seq[BlockBody]


  StatelessSyncRef* = ref object
    workQueue: seq[WantedBlocks]
    chain: ChainRef
    peerPool: PeerPool
    trustedPeers: HashSet[Peer]
    hasOutOfOrderBlocks: bool
    busyPeers: HashSet[Peer]
    knownByPeer: Table[Peer, HashToTime]
    lastCleanup: Time

template endBlockNumber(ctx: StatelessSyncRef): BlockNumber =
  ctx.chain.com.syncHighest

template `endBlockNumber=`(ctx: StatelessSyncRef, number: BlockNumber) =
  ctx.chain.com.syncHighest = number

template finalizedBlock(ctx: StatelessSyncRef): BlockNumber =
  ctx.chain.com.syncCurrent

template `finalizedBlock=`(ctx: StatelessSyncRef, number: BlockNumber) =
  ctx.chain.com.syncCurrent = number


proc onPeerConnected(ctx: StatelessSyncRef, peer: Peer) =
  trace "New candidate for sync", peer
  # ctx.startSyncWithPeer(peer)

proc onPeerDisconnected(ctx: StatelessSyncRef, p: Peer) =
  trace "peer disconnected ", peer = p
  ctx.trustedPeers.excl(p)
  ctx.busyPeers.excl(p)
  ctx.knownByPeer.del(p)

proc hash*(p: Peer): Hash = hash(cast[pointer](p))

proc init*(T: type StatelessSyncRef): T =
  new result

proc start*(ctx: StatelessSyncRef) =
  discard
  # try:
  #   var blockHash: Hash256
  #   let
  #     db  = ctx.chain.db
  #     com = ctx.chain.com

  #   if not db.getBlockHash(ctx.finalizedBlock, blockHash):
  #     debug "StatelessSync.start: Failed to get blockHash", number=ctx.finalizedBlock
  #     return

  #   if com.consensus == ConsensusType.POS:
  #     debug "Fast sync is disabled after POS merge"
  #     return

  #   ctx.chain.com.syncStart = ctx.finalizedBlock
  #   info "Fast Sync: start sync from",
  #     number=ctx.chain.com.syncStart,
  #     hash=blockHash

  # except CatchableError as e:
  #   debug "Exception in StatelessSync.start()",
  #     exc = e.name, err = e.msg

  # var po = PeerObserver(
  #   onPeerConnected:
  #     proc(p: Peer) {.gcsafe.} =
  #       ctx.onPeerConnected(p),
  #   onPeerDisconnected:
  #     proc(p: Peer) {.gcsafe.} =
  #       ctx.onPeerDisconnected(p))
  # po.setProtocol eth
  # ctx.peerPool.addObserver(ctx, po)

proc stop*(ctx: StatelessSyncRef) =
  discard
