Helper = require 'hubot-test-helper'
helper = new Helper '../scripts/in_network.coffee'

co = require 'co'
expect = require('chai').expect
sinon = require('sinon')

process.env.EXPRESS_PORT = 8080
process.env.EXPRESS_BIND_ADDRESS = 'localhost'
process.env.SURFER_SUBNET_WITH_MASK = '127.0.0.1/32'

describe 'registration', ->

  beforeEach ->
    @room = helper.createRoom()
    @env = process.env

    @token_regexp = /reg_token_(.*)/

  afterEach ->
    @room.destroy()

  context 'user registers at surfer', ->

    beforeEach ->
      @room.user.say 'alice', '@hubot register me'

    it 'should reply to user with link', ->
      brain_keys = Object.keys(@room.robot.brain.data._private)
      expect(brain_keys).to.lengthOf 1
      token = @token_regexp.exec(brain_keys[0])[1]

      link = (
        "http://#{@env.EXPRESS_BIND_ADDRESS}:#{@env.EXPRESS_PORT}/" +
        "hubot/register/#{token}/"
      )
      expect(@room.messages).to.eql [
        ['alice', '@hubot register me']
        ['hubot', "@alice Please, open link on your device #{link}"]
      ]

  it 'should not reply to user with link', ->
    @room.user.say 'bob', 'register me'
    expect(@room.messages).to.eql [
      ['bob',   'register me']
    ]

