# Configuration:
#  SURFER_SUBNET_WITH_MASK - ip address with subnet mask, ie 192.168.1.0/24
#
# Commands:
#  hubot ping me when <username> come to the office - send private message when <user_id> come to office
#  hubot register me - render the link to register personaldevice
#

Promise = require "bluebird"
arp = Promise.promisifyAll require 'node-arp'
ping = Promise.promisifyAll require("net-ping")
IpSubnetCalculator = require 'ip-subnet-calculator'
suid = require('rand-token').suid

class UserMACBinder

  key = 'local_network_macs'

  constructor: (@robot) ->

  bind: (mac, username) ->
    networkMACs = @robot.brain.get(key) or {}
    networkMACs[mac] = username
    @robot.brain.set key, networkMACs

  getByMAC: (mac) ->
    macs = @robot.brain.get(key) or {}
    macs[mac]


class SubNetSurfer
  constructor: (@robot, @network, @subnet) ->
    @brainKey = 'live_macs'

  startSurf: () ->
    console.log('Start surfing')
    @network.mapIpWithMask(@subnet)
    .map (ip) =>
      @network.pingIP(ip).then () ->
        ip
      .catch(()->)
    .filter((ip) -> ip)
    .map (ip) =>
      @network.getMACByIP(ip)
      .then (mac) ->
        {ip: ip, mac: mac}
      .catch () ->
    .filter((ip_mac) -> ip_mac and ip_mac.mac isnt '(incomplete)')
    .map((ip_mac) -> ip_mac.mac)
    .then (live_macs) =>
      @updateMacs(live_macs)
      @robot.emit("macs_updated", @)
    .catch (err) =>
      console.log(err)
      @robot.emit("macs_updated", @)

  updateMacs: (live_macs) ->
    live_macs = new Set(live_macs)
    old_live_macs = @robot.brain.get(@brainKey) or new Set()
    old_live_macs.forEach (mac) =>
      @robot.emit("mac_down", mac) if not live_macs.has(mac)
    live_macs.forEach (mac) =>
      @robot.emit("mac_up", mac) if not old_live_macs.has(mac)
    @robot.brain.set @brainKey, live_macs


class Network

  pingSession = ping.createSession()

  getMACByIP: (ip) ->
    arp.getMACAsync ip

  pingIP: (ip) ->
    pingSession.pingHostAsync ip

  ipRange: (ipWithMask) ->
    [ip, mask] = ipWithMask.split('/')
    IpSubnetCalculator.calculateSubnetMask(ip, mask)

  mapIpWithMask: (ipWithMask) ->
    range = @ipRange(ipWithMask)
    Promise.map [range.ipLow..range.ipHigh], (ipDecimal) ->
      IpSubnetCalculator.toString(ipDecimal)


class Notifier

  brainKey = 'track_notifier_'

  constructor: (@robot, @binder) ->

  track: (who, byWhom) ->
    key = @renderKey(who)
    trackers = @robot.brain.get(key) or new Set()
    trackers.add(byWhom)
    @robot.brain.set(key, trackers)
    console.log "#{byWhom} tracks #{who}"

  notifyTrackers: (mac) ->
    who = @binder.getByMAC(mac)
    if not who
      return
    key = @renderKey(who)
    trackers = @robot.brain.get(key) or new Set()
    Promise.map trackers, (i) =>
      user = @robot.brain.userForName i
      @robot.send user, "#{who} come to the office!"
    .then =>
      @robot.brain.remove key

  renderKey: (who) ->
    brainKey + who

  getMessageUser: (res) ->
    res.message.user.name

  getRegistrationUser: (username) ->
    user = @robot.brain.userForId(username) or @robot.brain.userForName(username)
    user.name if user


class TokenGenerator

  brainKey = 'reg_token_'
  tokenSize = 16
  tokenLifeTime = 120*1000

  constructor: (@robot) ->

  generate: (user) ->
    token = suid(tokenSize)
    key = @getKey token
    @robot.brain.set key, user
    setTimeout () =>
      @robot.brain.remove key
    , tokenLifeTime
    token

  getKey: (token) ->
    brainKey + token

  getUser: (token) ->
    key = @getKey token
    user = @robot.brain.get key
    @robot.brain.remove key
    user


module.exports = (robot) ->

  surfCountDown = 1000
  subnet = process.env.SURFER_SUBNET_WITH_MASK
  publicPort = (process.env.EXPRESS_PORT or 8080)
  if publicPort is 80
    publicHostname = process.env.EXPRESS_BIND_ADDRESS
  else
    publicHostname = process.env.EXPRESS_BIND_ADDRESS + ":#{publicPort}"
  trustProxy = process.env.TRUST_PROXY

  robot.tokenGenerator = new TokenGenerator(robot)
  robot.binder = new UserMACBinder(robot)
  robot.network = new Network()
  robot.notifier = new Notifier(robot, robot.binder)
  robot.surfer = new SubNetSurfer(robot, robot.network, subnet)
  robot.surfer.startSurf()

  robot.on "mac_down", (mac) ->
    console.log "#{mac} down"

  robot.on "mac_up", (mac) ->
    console.log "#{mac} up"
    robot.notifier.notifyTrackers mac

  robot.on "macs_updated", (surfer) ->
    setTimeout () ->
      robot.surfer.startSurf()
    , surfCountDown

  robot.respond /ping me when (.*) come to the office/i, (res) ->
    username = res.match[1]
    author = robot.notifier.getMessageUser res
    user = robot.notifier.getRegistrationUser username
    if user
      robot.notifier.track user, author
    else
      res.reply 'No such user.'

  robot.respond /register me/i, (res) ->
    token = robot.tokenGenerator.generate robot.notifier.getMessageUser res
    url = "http://#{publicHostname}/hubot/register/#{token}/"
    res.reply "Please, open link on your device #{url}"

  robot.router.set 'trust proxy', trustProxy

  robot.router.get '/hubot/register/:token/', (req, res) ->
    username = robot.tokenGenerator.getUser req.params.token
    ip = req.ip
    if not ip
      res.send 'Can not detect your IP.'
      return
    if not username
      res.send 'Token invalid.'
      return

    robot.network.getMACByIP(ip)
    .then (mac) ->
      if mac isnt '(incomplete)'
        robot.binder.bind mac, username
        robot.send robot.brain.userForName(username), "#{mac} was added."
      else
        console.log "Fail to register: ip #{ip}, username #{username}"
    .catch (err) ->
      console.log "Fail to register: ip #{ip}, username #{username}\n #{err}"
    res.send 'Register user.'
