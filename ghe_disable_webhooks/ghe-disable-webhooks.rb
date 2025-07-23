#!/bin/ruby
# frozen_string_literal: true
#
# Script to disable GitHub Enterprise Server webhooks by ID.
#
# Usage:
#   ./ghes-run scripts/ghes-disable-webhooks --ids 1,2,3
#
# Options:
#   --ids HOOK_IDS    Comma-separated list of Webhook IDs to disable (required)
#   --dry-run         Show what would be done, but do not perform any changes
#
# Example:
#   ./ghes-run scripts/ghes-disable-webhooks --ids 42,43 --dry-run
#
# This script will locate active webhooks by ID and disable them. 
# It supports enterprise, organization, and repository webhooks.
#
# Should work reliably on GHES 3.13.x ~ 3.16.x

require "logger"
require "optparse"
require "ostruct"

# Reset encoding to UTF-8 to avoid encoding errors
Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

# Initialize options
options = OpenStruct.new

# Parse arguments
option_parser = OptionParser.new do |opts|
  opts.banner = "Usage: ghes-manage-webhooks [options]"
  opts.separator ""

  opts.on("--ids HOOK_IDS", "Comma-separated list of Webhook IDs") do |ids|
    options.ids = ids
  end

  opts.on("--dry-run", "Show what would be done.") do |dry_run|
    options.dry_run = dry_run
  end

  opts.on_tail("-h", "--help", "Show this message") do
    puts opts
    exit
  end
end

option_parser.parse!(ARGV)

# Check required arguments
if options.ids.nil?
  raise ArgumentError, "Webhook IDs (--ids ids) is required"
end

# Assign option variables for better readability
ids = options.ids

ids.split(",").each do |hook_id|
  hook = Hook.includes(:installation_target).find_by(id: hook_id, active: true)

  next if !hook

  begin
    case hook.installation_target
    when Repository
      hook_target = hook.installation_target.nwo
      hook_target_type = hook.installation_target_type
    when User
      hook_target = hook.installation_target.login
      hook_target_type = hook.installation_target.type
    when Business
      hook_target = "Site Admin"
      hook_target_type = "Global"
    when Integration
      hook_target = hook.installation_target.name
      hook_target_type = "Integration"
    else
      # puts "Unable to locate a webhook with id #{hook_id}"
      next
    end

    puts "Disabling #{hook_target_type} webhook #{hook.url} on #{hook_target}"

    hook.disable unless options.dry_run
  rescue Error => e
    puts "#{e}: webhook id #{hook_id}"
    next
  end
end
