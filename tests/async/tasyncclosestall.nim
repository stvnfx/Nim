discard """
  outputsub: "send has errored. As expected. All good!"
  exitcode: 0
"""
import asyncdispatch, asyncnet

# This reproduces a case where a socket remains stuck waiting for writes
# even when the socket is closed.
const
  port = Port(50726)
  timeout = 5000

var sent = 0

proc keepSendingTo(c: AsyncSocket) {.async.} =
  while true:
    # This write will eventually get stuck because the client is not reading
    # its messages.
    let sendFut = c.send("Foobar" & $sent & "\n")
    if not await withTimeout(sendFut, timeout):
      # The write is stuck. Let's simulate a scenario where the socket
      # does not respond to PING messages, and we close it. The above future
      # should complete after the socket is closed, not continue stalling.
      echo("Socket has stalled, closing it")
      c.close()

      let timeoutFut = withTimeout(sendFut, timeout)
      yield timeoutFut
      if timeoutFut.failed:
        echo("send has errored. As expected. All good!")
        quit(QuitSuccess)
      if timeoutFut.read():
        raise newException(ValueError, "Test failed. Send was expected to fail.")
      else:
        raise newException(ValueError, "Test failed. Send future is still stalled.")
    sent.inc(1)

proc startClient() {.async.} =
  let client = newAsyncSocket()
  await client.connect("localhost", port)
  echo("Connected")

  let firstLine = await client.recvLine()
  echo("Received first line as a client: ", firstLine)
  echo("Now not reading anymore")
  while true: await sleepAsync(1000)

proc debug() {.async.} =
  while true:
    echo("Sent ", sent)
    await sleepAsync(1000)

proc server() {.async.} =
  var s = newAsyncSocket()
  s.setSockOpt(OptReuseAddr, true)
  s.bindAddr(port)
  s.listen()

  # We're now ready to accept connections, so start the client
  asyncCheck startClient()
  asyncCheck debug()

  while true:
    let client = await accept(s)
    asyncCheck keepSendingTo(client)

when isMainModule:
  waitFor server()

