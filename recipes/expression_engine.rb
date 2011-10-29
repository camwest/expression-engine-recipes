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
    set :backup_file, "db_backups/#{dbname}-snapshot-#{backup_time}.sql"
  end

  task :local_backup_name do
    now = Time.now
    run "mkdir -p db_backups_from_local"
    backup_time = [now.year, now.month, now.day, now.hour, now.min, now.sec].join('-')
    set :local_backup_file, "db_backups_from_local/#{dbname}-snapshot-#{backup_time}.sql"
  end

  desc "dumps a database to /db_backups"
  task :dump do
    backup_name
    run "mysqldump --add-drop-table -u #{dbuser} -p #{dbname} | bzip2 -c > #{backup_file}.bz2" do |ch, stream, out|
      ch.send_data "#{dbpass}\n" if out=~ /^Enter password:/
    end
  end

  task :local_dump do
    system "mysqldump --add-drop-table -u root #{dbname} | bzip2 -c > /tmp/#{dbname}-snapshot.sql.bz2"
  end

  task :clone_to_local do
    backup_name
    dump
    get "#{backup_file}.bz2", "/tmp/#{application}.sql.gz"
    system "bzcat /tmp/#{application}.sql.gz | mysql -u root #{dbname}"
  end

  desc "Pushes the database on to staging"
  task :deploy_database do
    #first backup the database
    backup_name
    dump

    #dump a local copy of the database
    local_dump

    #create the local backup directory on the server if it doesn't exist
    local_backup_name

    #upload the file
    put(File.read("/tmp/#{dbname}-snapshot.sql.bz2"), "#{local_backup_file}.bz2", :mode => 0666)

    #import the database
    run("bzcat #{local_backup_file}.bz2 | mysql -u #{dbuser} --password=\"#{dbpass}\" #{dbname}", { :shell => false})
  end

  desc "Updates the file paths on production / staging"
  task :update_file_upload_paths do

    #set the file name
    now = Time.now
    creation_time = [now.year, now.month, now.day, now.hour, now.min, now.sec].join('-')

    set :upload_file_name, "/tmp/#{dbname}_upload_locations-#{creation_time}.txt"

    #dump a list of file upload paths
    run "mysql -u #{dbuser} --password=\"#{dbpass}\" --database=#{dbname} --execute=\"SELECT id, url from exp_upload_prefs INTO OUTFILE '#{upload_file_name}'\""

    #get the file upload paths locally
    get("#{upload_file_name}", "#{upload_file_name}")

    urls = []

    #open tthe file
    file = File.open("#{upload_file_name}")
    file.readlines.each do |line|

      db_row = line.split("\t")
      row_id = db_row[0]
      upload_path = db_row[1]

      server_path = "#{path_to_src_dir}/public#{upload_path}"

      #update the permissions while we're here
      run "chmod 777 #{server_path}"

      #for each entry update the database
      run "mysql -u #{dbuser} --password=\"#{dbpass}\" --database=#{dbname} --execute=\"UPDATE exp_upload_prefs SET server_path='#{server_path}' WHERE id = #{row_id}\""
    end
  end

  desc "Copies any uploads from the server to the same folder locally"
  task :clone_uploads_to_local do
    cmd = [
      "cd #{path_to_src_dir}",
      "tar -cjf uploads.tar #{path_to_uploads_dir}"
    ].join(" && ")

    run cmd

    get("#{path_to_src_dir}/uploads.tar", "/tmp/uploads.tar")

    run "rm -Rf #{path_to_src_dir}/uploads.tar"

    cmd = [
      "tar -xvf /tmp/uploads.tar",
      "rm -Rf /tmp/uploads.tar"
    ].join(" && ")

    system cmd
  end

  after "ee:deploy_database", "ee:update_file_upload_paths"
  before "ee:deploy", "ee:git_push"
end