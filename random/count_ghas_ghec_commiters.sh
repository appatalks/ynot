ghe-console -y <<'ENDSCRIPT'
ActiveRecord::Base.connected_to(role: :reading) do
  puts "Version 0.2.0"
  emails = Set.new
  start_time = 90.days.ago.beginning_of_day
  Repository.where(active: true).find_each do |repo|
    Push
      .where(repository: repo)
      .where("created_at >= ?", start_time)
      .find_each do |push|
        push.commits_pushed.each do |commit|
          commit.author_emails.each do |email|
            emails << email unless UserEmail.belongs_to_a_bot?(email)
          end
        end
      end
  end
  users = Set.new
  emails.each_slice(1000) do |batch|
    emails_to_users_hash = User.find_by_emails(batch)
    active_users = emails_to_users_hash.values.select do |user|
      !(user.disabled? || user.suspended?)
    end
    users.merge(active_users)
  end
  puts "Committers in the past 90d: #{users.size}"
end
ENDSCRIPT
