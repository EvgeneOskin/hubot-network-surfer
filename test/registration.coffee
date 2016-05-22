Helper = require 'hubot-test-helper'
helper = new Helper '../scripts/in_network.coffee'

co = require 'co'
expect = require('chai').expect
rp = require 'request-promise'
Promise = require 'bluebird'
dns = Promise.promisifyAll require 'dns'
os = require 'os'

process.env.EXPRESS_PORT = 8080

describe 'registration', ->

  beforeEach ->
    @get_registration_link = () =>
      token_regexp = /reg_token_(.*)/
      brain_keys = Object.keys(@room.robot.brain.data._private)
      expect(brain_keys).to.lengthOf 1
      token =token_regexp.exec(brain_keys[0])[1]
      "http://#{@env.EXPRESS_BIND_ADDRESS}:#{@env.EXPRESS_PORT}/" +
      "hubot/register/#{token}/"
    dns.lookupAsync os.hostname()
    .then (address) =>
      process.env.EXPRESS_BIND_ADDRESS = address
      process.env.SURFER_SUBNET_WITH_MASK = "#{address}/32"
      @room = helper.createRoom()
      @env = process.env

  afterEach ->
    @room.destroy()

  context 'user registers at surfer', ->

    beforeEach ->
      @room.user.say 'alice', '@hubot register me'

    it 'should reply to user with link', ->
      link = @get_registration_link()
      expect(@room.messages).to.eql [
        ['alice', '@hubot register me']
        ['hubot', "@alice Please, open link on your device #{link}"]
      ]

    it 'should register user', ->
      link = @get_registration_link()
      rp(link)
      .then (res) ->
        expect(res).to.eql 'Register user.'
      .delay(100)
      .then =>
        expect(@room.messages[2][1]).to.match /(.{2})(:.{2}){5} was added./
        mac = /(.*) was added./.exec(@room.messages[2][1])[1]
        macs = @room.robot.brain.get 'local_network_macs'
        expect(macs[mac]).to.eql 'alice'

  it 'should not reply to user with link', ->
    @room.user.say 'bob', 'register me'
    expect(@room.messages).to.eql [
      ['bob',   'register me']
    ]

