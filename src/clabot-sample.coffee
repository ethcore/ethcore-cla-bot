'use strict'

express = require 'express'
jade = require 'jade'
fs = require 'fs'
http = require 'http'
https = require 'https'
data = require './lib/data'

passport = require('passport')
GitHubStrategy = require('passport-github').Strategy
bodyParser = require('body-parser')

# create secrets object
secrets = {}
secrets[process.env.GITHUB_REPO_OWNER] = {}
secrets[process.env.GITHUB_REPO_OWNER]['rhododendron'] = process.env.HUB_SECRET
secrets[process.env.GITHUB_REPO_OWNER]['parity-ethereum'] = process.env.HUB_SECRET
secrets[process.env.GITHUB_REPO_OWNER]['sol-rs'] = process.env.HUB_SECRET
secrets[process.env.GITHUB_REPO_OWNER]['substrate'] = process.env.HUB_SECRET
secrets[process.env.GITHUB_REPO_OWNER]['polkadot'] = process.env.HUB_SECRET
secrets[process.env.GITHUB_REPO_OWNER][''] = process.env.HUB_SECRET

# domain url
domain = process.env.DOMAIN
domain = 'https://' + hostname + '.cla.parity.io'
console.log('Serving Github Repos: ', process.env.GITHUB_REPO_OWNER)
console.log('Domain is: ', domain)

# set up authentication
passport.use new GitHubStrategy
  clientID: process.env.CLIENT_ID
  clientSecret: process.env.CLIENT_SECRET
  callbackURL: domain + "/auth/github/callback"
, (accessToken, refreshToken, profile, cb) ->
  data.saveOrCreateSigner profile, (err) ->
    cb(err, profile)

passport.serializeUser (user, done) ->
  done null, user.id

passport.deserializeUser (id, done) ->
  data.getProfile id, (err, profile) ->
    done null, profile

app = express()

appObj =
  app: app
  getContractors: data.getContractors
  token: process.env.GITHUB_TOKEN
  secrets: secrets
  skipCollaborators: true
  skipContributors: true
  templateData:
    link: "#{domain}"
    maintainer: 'paritytech'
  templates:
    notYetSigned: """
It looks like @<%=sender%> hasn't signed our **C**ontributor **L**icense **A**greement, yet.

> The purpose of a CLA is to ensure that the guardian of a project's outputs has the necessary ownership or grants of rights over all contributions to allow them to distribute under the chosen licence.
[Wikipedia](http://en.wikipedia.org/wiki/Contributor_License_Agreement)

You can read and sign our full Contributor License Agreement at the following URL: [#{process.env.DOMAIN}](#{process.env.DOMAIN})

Once you've signed, please reply to this thread with `[clabot:check]` to prove it.

Many thanks,

Parity Technologies CLA Bot
      """
    confirmSigned: """
Hey @<%= sender %>,

Thank you for signing the **C**ontributor **L**icense **A**greement. This Pull Request is ready to go!

Many thanks,

Parity Technologies CLA Bot
      """
    alreadySigned: """
It looks like <% if (check){  %>@<%= sender %><% } else { %>this contributor<% } %> signed our Contributor License Agreement. :+1:

Many thanks,

Parity Technologies CLA Bot
      """


app.use bodyParser.json
  verify: (req, res, buf, encoding) -> req.rawBody = buf

app.use bodyParser.urlencoded
  extended: false
  verify: (req, res, buf, encoding) -> req.rawBody = buf

app.use (req,res,next) ->
  req.clabotOptions = appObj
  next()

app.use express.cookieParser()
app.use express.session({ secret: process.env.SESSION_SECRET })
app.use passport.initialize()
app.use passport.session()
app.use require('connect-assets')()
app.use express.compress()

app.get '/', (req,res) ->
  if req.isAuthenticated()
    res.redirect '/form/parity'
  else
    res.render 'landing.jade', layout: no

console.log('data', appObj.templateData)
app = require('clabot').createApp appObj

# auth
app.get '/auth/github', passport.authenticate('github')

app.get '/auth/github/callback', passport.authenticate('github', { failureRedirect: '/login' }), (req, res) ->
    res.redirect('/form/parity')

app.get '/logout', (req,res) ->
  req.session.destroy()
  res.redirect '/'


app.get '/form/:project/:kind?', (req, res) ->

  unless req.isAuthenticated()
    res.redirect('/')
    return

  project = req.params.project
  # Makes no sense, yet. Extensible in the future.
  if project isnt 'clabot' then project = 'clabot'
  kind    = req.params.kind?.toLowerCase() || 'Individual'
  kind    = kind.charAt(0).toUpperCase() + kind.slice 1
  if kind isnt 'Entity' then kind = 'Individual'

  res.render 'form.jade',
    user : req.user
    layout: no

app.get '/sign', data.save

port = process.env.PORT or 443

if process.env.SSL_KEY and process.env.SSL_CERT
  app = https.createServer
    key: fs.readFileSync process.env.SSL_KEY
    cert: fs.readFileSync process.env.SSL_CERT
  , app
else
  app = http.createServer()

app.listen port
console.log "Listening on #{port}"
