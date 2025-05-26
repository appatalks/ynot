#!/usr/bin/env ruby
require 'octokit'

Octokit.configure do |c|
  c.api_endpoint = "https://HOSTNAME/api/v3"
  c.auto_paginate = true
  c.ssl_verify_mode = OpenSSL::SSL::VERIFY_NONE
end

org_name = "babytime"

client = Octokit::Client.new(access_token: "ghp_****")
org_repos = client.org_repos(org_name)

org_repos.each do |r|
  if r.private
    puts "#{r.name} is already private"
    next
  end
  puts "#{r.name} is moving to private"
  client.set_private(r.full_name)
end
