import eth/keys

var key = ""
var publicAddress = Privatekey.fromHex(key).get.toPublicKey().toCanonicalAddress()
echo publicAddress
