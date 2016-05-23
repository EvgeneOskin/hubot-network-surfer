Helper = require 'hubot-test-helper'
helper = new Helper '../scripts/in_network.coffee'

co = require 'co'
expect = require('chai').expect
rp = require 'request-promise'
Promise = require 'bluebird'
dns = Promise.promisifyAll require 'dns'
os = require 'os'

describe 'Notify about coming in', ->

  beforeEach ->
    @bobMac = 'a8:26:d9:55:6d:c7'
    dns.lookupAsync os.hostname()
    .then (address) =>
      process.env.EXPRESS_BIND_ADDRESS = address
      process.env.SURFER_SUBNET_WITH_MASK = "#{address}/32"
      @room = helper.createRoom()
      @env = process.env

  afterEach ->
    @room.destroy()

  context 'alice track bob', ->

    beforeEach ->
      @room.user.say 'bob', '@alice hi'
      @room.user.say 'alice', '@bob hi'
      @room.robot.binder.bind @bobMac, 'bob'
      @room.robot.notifier.track 'bob', 'alice'

    it 'ping tracker', ->
      @room.robot.emit 'mac_up', @bobMac
      expect(@room.messages).to.eql [
        ['bob', '@alice hi']
        ['alice', '@bob hi']
        ['hubot', 'bob come to the office!']
      ]
