# Nimbus - Types, data structures and shared utilities used in network sync
#
# Copyright (c) 2018-2021 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE) or
#    http://www.apache.org/licenses/LICENSE-2.0)
#  * MIT license ([LICENSE-MIT](LICENSE-MIT) or
#    http://opensource.org/licenses/MIT)
# at your option. This file may not be copied, modified, or
# distributed except according to those terms.

## Aristo (aka Patricia) DB records merge test

import
  std/[algorithm, sequtils, sets],
  eth/common,
  stew/results,
  unittest2,
  ../../nimbus/db/aristo/[
    aristo_desc, aristo_debug, aristo_error, aristo_merge, aristo_nearby],
  ../../nimbus/sync/snap/range_desc,
  ./test_helpers

# ------------------------------------------------------------------------------
# Private helpers
# ------------------------------------------------------------------------------

proc fwdWalkLeafsCompleteDB(
    db: AristoDbRef;
    tags: openArray[NodeTag];
    noisy: bool;
      ): tuple[visited: int, error:  AristoError] =
  let
    tLen = tags.len
  var
    error = AristoError(0)
    tag = (tags[0].u256 div 2).NodeTag
    n = 0
  while true:
    let rc = tag.nearbyRight(db.lRoot, db) # , noisy)
    #noisy.say "=================== ", n
    if rc.isErr:
      if rc.error != NearbyBeyondRange:
        noisy.say "***", "[", n, "/", tLen-1, "] fwd-walk error=", rc.error
        error = rc.error
        check rc.error == AristoError(0)
      elif n != tLen:
        error = AristoError(1)
        check n == tLen
      break
    if tLen <= n:
      noisy.say "***", "[", n, "/", tLen-1, "] fwd-walk -- ",
        " oops, too many leafs (index overflow)"
      error = AristoError(1)
      check n < tlen
      break
    if rc.value != tags[n]:
      noisy.say "***", "[", n, "/", tLen-1, "] fwd-walk -- leafs differ,",
        " got=", rc.value.pp(db),
        " wanted=", tags[n].pp(db) #, " db-dump\n    ", db.pp
      error = AristoError(1)
      check rc.value == tags[n]
      break
    if rc.value < high(NodeTag):
      tag = (rc.value.u256 + 1).NodeTag
    n.inc

  (n,error)


proc revWalkLeafsCompleteDB(
    db: AristoDbRef;
    tags: openArray[NodeTag];
    noisy: bool;
      ): tuple[visited: int, error:  AristoError] =
  let
    tLen = tags.len
  var
    error = AristoError(0)
    delta = ((high(UInt256) - tags[^1].u256) div 2)
    tag = (tags[^1].u256 + delta).NodeTag
    n = tLen-1
  while true: # and false:
    let rc = tag.nearbyLeft(db.lRoot, db) # , noisy)
    if rc.isErr:
      if rc.error != NearbyBeyondRange:
        noisy.say "***", "[", n, "/", tLen-1, "] rev-walk error=", rc.error
        error = rc.error
        check rc.error == AristoError(0)
      elif n != -1:
        error = AristoError(1)
        check n == -1
      break
    if n < 0:
      noisy.say "***", "[", n, "/", tLen-1, "] rev-walk -- ",
        " oops, too many leafs (index underflow)"
      error = AristoError(1)
      check 0 <= n
      break
    if rc.value != tags[n]:
      noisy.say "***", "[", n, "/", tLen-1, "] rev-walk -- leafs differ,",
        " got=", rc.value.pp(db),
        " wanted=", tags[n]..pp(db) #, " db-dump\n    ", db.pp
      error = AristoError(1)
      check rc.value == tags[n]
      break
    if low(NodeTag) < rc.value:
      tag = (rc.value.u256 - 1).NodeTag
    n.dec

  (tLen-1 - n, error)

# ------------------------------------------------------------------------------
# Public test function
# ------------------------------------------------------------------------------

proc test_nearbyKvpList*(
    noisy: bool;
    list: openArray[ProofTrieData];
    resetDb = false;
      ) =
  var
    db = AristoDbRef()
    tagSet: HashSet[NodeTag]
  for n,w in list:
    if resetDb:
      db = AristoDbRef()
      tagSet.reset
    let
      lstLen = list.len
      lTabLen = db.lTab.len
      leafs = w.kvpLst
      added = db.merge leafs

    check added.error == AristoError(0)
    check db.lTab.len == lTabLen + added.merged
    check added.merged + added.dups == leafs.len

    for w in leafs:
      tagSet.incl w.pathTag

    let
      tags = tagSet.toSeq.sorted
      fwdWalk = db.fwdWalkLeafsCompleteDB(tags, noisy=true)
      revWalk = db.revWalkLeafsCompleteDB(tags, noisy=true)

    check fwdWalk.error == AristoError(0)
    check revWalk.error == AristoError(0)
    check fwdWalk == revWalk

    if {fwdWalk.error, revWalk.error} != {AristoError(0)}:
      noisy.say "***", "<", n, "/", lstLen-1, "> db dump",
        "\n   post-state ", db.pp,
        "\n"
      break

    #noisy.say "***", "sample ",n,"/",lstLen-1, " visited=", fwdWalk.visited

# ------------------------------------------------------------------------------
# End
# ------------------------------------------------------------------------------