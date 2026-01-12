# Check LFS Disk usage on GHES
# If you want the report to include only org-owned repos, uncomment the "`next unless r.owner&.organization?`"
# Tested GHES 3.17.x

cat <<'RUBY' | ghe-console -y
require "csv"
include ActionView::Helpers::NumberHelper

# Aggregate LFS usage by repository_network_id.
# - media_blobs links repos/networks to storage_blobs
# - storage_blobs.size is the byte size
# - DISTINCT prevents double-counting the same blob within a network
sql = <<~SQL
  SELECT mb.repository_network_id AS repository_network_id,
         COUNT(*) AS lfs_objects,
         COALESCE(SUM(sb.size), 0) AS lfs_bytes
  FROM (
    SELECT DISTINCT repository_network_id, storage_blob_id
    FROM media_blobs
    WHERE repository_network_id IS NOT NULL
      AND storage_blob_id IS NOT NULL
  ) mb
  INNER JOIN storage_blobs sb ON sb.id = mb.storage_blob_id
  GROUP BY mb.repository_network_id
SQL

rows = ActiveRecord::Base.connection.exec_query(sql).to_a
usage_by_network = rows.each_with_object({}) do |row, h|
  h[row.fetch("repository_network_id").to_i] = {
    objects: row.fetch("lfs_objects").to_i,
    bytes: row.fetch("lfs_bytes").to_i,
  }
end

out = "/tmp/lfs-repositories-report.csv"
written = 0

CSV.open(out, "wb") do |csv|
  csv << ["nwo", "lfs_objects", "lfs_bytes_human", "lfs_bytes"]

  Repository.find_each do |r|
    # If you want to match your old behavior (org-owned repos only), uncomment:
    # next unless r.owner&.organization?

    usage = usage_by_network[r.network_id]
    next if usage.nil? || (usage[:bytes] == 0 && usage[:objects] == 0)

    csv << [r.nwo, usage[:objects], number_to_human_size(usage[:bytes]), usage[:bytes]]
    written += 1
  end
end

puts "Networks with LFS: #{usage_by_network.size}"
puts "Repos written: #{written}"
puts "Wrote: #{out}"
RUBY
