###

dnschain
http://dnschain.org

Copyright (c) 2014 okTurtles Foundation

This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at http://mozilla.org/MPL/2.0/.

###

net = require "net" # TODO: Fix this, it's in the globals.

parse2Bytes = (buf) -> (buf[0] << 8) | buf[1]
parse3Bytes = (buf) -> (buf[0] << 16) | (buf[1] << 8) | buf[2]

# http://tools.ietf.org/html/rfc5246#section-7.4.1
# http://stackoverflow.com/questions/17832592/extract-server-name-indication-sni-from-tls-client-hello
# Parse binary data and return an object containing the TLS Hello data or null if an error occured.
parseHTTPS = (packet) ->
    res = {}
    res.contentType = packet[0]
    res.recordVersion = packet[1..2]
    res.recordLength = parse2Bytes packet[3..4]

    res.handshakeType = packet[5]
    res.handshakeLength = parse3Bytes packet[6..8]
    res.handshakeVersion = packet[9..10]
    res.random = packet[11..42]

    res.sessionIDlength = packet[43]
    pos = res.sessionIDlength + 43 + 1

    res.cipherSuitesLength = parse2Bytes packet[pos..(pos+1)]
    pos += res.cipherSuitesLength + 2

    res.compressionMethodsLength = packet[pos]
    pos += res.compressionMethodsLength + 1

    res.extensionsLength = parse2Bytes packet[pos..(pos+1)]
    pos += 2

    extensionsEnd = pos + res.extensionsLength - 1
    res.type = -1
    res.length = 0
    # Loop over extension blocks until we find the SNI block
    while res.type != 0 and pos < extensionsEnd
        pos += res.length
        res.type = parse2Bytes packet[pos..(pos+1)]
        res.length = parse2Bytes packet[(pos+2)..(pos+3)]

    res.SNIlength = parse2Bytes packet[(pos+4)..(pos+5)]
    res.serverNameType = packet[(pos+6)]
    pos += 7
    # The SNI type number is 0. An SNI length shorter than 4 bytes indicates an invalid header.
    if res.type == 0 and res.SNIlength >= 4
        res.hostLength = parse2Bytes packet[pos..(pos+1)]
        pos += 2
        res.host = packet[pos..(pos+res.hostLength-1)].toString "utf8"
        res
    else
        null

# Open a TCP socket to a remote host.
getStream = (host, port, cb) ->
    try
        done = (err, s) ->
            done = ->
            cb err, s
        s = net.createConnection {host, port}, ->
            done null, s
        s.on "error", (err) -> s.destroy()
        s.on "close", -> s.destroy()
        s.on "timeout", -> s.destroy()
    catch err
        done err

# Received raw TCP data in chunked mode and attempt to extract Hello data
# after every chunk. Return as soon as the Hello data has been obtained.
getClientHello = (c, cb) ->
    received = []
    buf = new Buffer []
    done = (err, host, buf) ->
        c.removeAllListeners("data")
        done = ->
        cb err, host, buf
    c.on "data", (data) ->
        c.pause()
        received.push data
        buf = Buffer.concat received
        ssl = parseHTTPS buf
        if ssl?.host?
            done null, ssl.host, buf
        else
            c.resume()
    c.on "timeout", ->
        c.destroy()
        done new Error "HTTPS getClientHello timeout"
    c.on "error", (err) ->
        c.destroy()
        done err
    c.on "close", ->
        c.destroy()
        done new Error "HTTPS socket closed"

module.exports = {getClientHello, getStream}