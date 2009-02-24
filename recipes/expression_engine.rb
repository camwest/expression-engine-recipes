namespace :ee do  
  desc "runs git pull origin master in httpdocs on the server"  
  task :deploy do
    cmd = [
      "cd #{path_to_src_dir}",
      "git pull origin master"
    ].join(" && ")    
    run cmd
  end
  
  desc "checks code into git"
  task :git_push do
    system "git push origin master"
  end

  desc "runs the rake production:deploy command"
  task :prepare_deploy do 
    system "rake production:deploy"
  end
  
  task :backup_name do
    now = Time.now
    run "mkdir -p db_backups"
    backup_time = [now.year, now.month, now.day, now.hour, now.min, now.sec].join('-')
    set :backup_file, "db_backups/bbdb-snapshot-#{backup_time}.sql"
  end
  
  desc "dumps a database to /db_backups"
  task :dump do
    backup_name
    run "mysqldump --add-drop-table -u #{dbuser} -p #{dbname} | bzip2 -c > #{backup_file}.bz2" do |ch, stream, out|
      ch.send_data "#{dbpass}\n" if out=~ /^Enter password:/
    end
  end
  
  task :clone_to_local do
    backup_name
    dump
    get "#{backup_file}.bz2", "/tmp/#{application}.sql.gz"
    system "bzcat /tmp/#{application}.sql.gz | mysql -u root #{dbname}"
  end
  
  # before "ee:deploy", "ee:prepare_deploy"  
  before "ee:deploy", "ee:git_push"
end