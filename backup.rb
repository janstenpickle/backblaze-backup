#!/usr/bin/env ruby
require 'tmpdir'
require 'yaml'
require 'json'
require 'fileutils'

@date_format='%m-%y'

defaults = YAML::load_file('/defaults.yaml')
config = defaults.merge(YAML::load_file(ENV['BACKUP_CONFIG']))
@date = DateTime.now
@day = @date.strftime('%d')
@month = @date.strftime(@date_format)
@months_retention = config['months_retention']

@backup_dir = File.join(config['backup_dir'], @month)
@bucket = config['bucket']
@passphrase = config['gpg_passphrase']
@b2_account_id = config['b2_account_id']
@b2_application_key = config['b2_application_key']
@b2_auth_retries = config['b2_auth_retries']

def b2_auth
  output = `b2 authorize_account "#{@b2_account_id}" "#{@b2_application_key}"`
  return true unless output.include?('bad_auth_token') || output.include?('expired_auth_token')
  false
end

def b2_auth_retry
  result = b2_auth
  retries = @b2_auth_retries

  while retries >= 0 && !result do
    result = b2_auth
    retries -= 1 
  end
  exit 1 unless result
end

def b2_download_file(filename, target)
  `b2 download_file_by_name #{@bucket} #{filename} #{target}`
end

def b2_upload_file(filename, target)
  `b2 upload_file --threads 2 #{@bucket} #{filename} #{target}`
end

def b2_list_files(pattern)
  JSON.load(`b2 list_file_names #{@bucket}`)['files'].select { |file| file['fileName'].start_with?(pattern) }
end

def decrypt_file(filename, target)
  `gpg --batch --yes --passphrase "#{@passphrase}" -o #{target} #{filename}`
end

def encrypt_file(filename, target)
  `gpg --batch --yes --passphrase "#{@passphrase}" -o #{target} --symmetric --force-mdc #{filename}`
end

def b2_delete_files(file_info)
  file_info.each do |file|
    `b2 delete_file_version #{file['fileName']} #{file['fileId']}`
  end
end

def clean_old_backups
  month_to_delete = @date.prev_month(@months_retention).strftime(@date_format)
  b2_delete_files(b2_list_files(month_to_delete))
end

def create_backup(dir, excludes = [])
  backup = dir.gsub(/(\/)+$/,'')
  backup_tar = "#{File.join(@backup_dir, backup)}.#{@day}.tar.gpg"
  backup_tar_remote = "#{File.join(@month, backup)}.#{@day}.tar.gpg"
  backup_meta = "#{File.join(@backup_dir, backup)}_metadata.snar"
  backup_meta_gpg = "#{backup_meta}.gpg"
  backup_meta_remote = "#{File.join(@month, backup)}_metadata.snar.gpg"

  exclude_list = excludes.map { |ex| "--exclude='#{ex}'" }.join(' ')
 
  if b2_list_files(backup_tar_remote).size == 0
    FileUtils.mkdir_p(File.dirname(backup_tar))
    if !File.exists?(backup_meta) && b2_list_files(backup_meta_remote).size == 1
      Dir.mktmpdir do |dir|
        tmp_meta = File.join(dir, File.basename(backup_meta_remote))
        b2_download_file(backup_meta_remote, tmp_meta)
        decrypt_file(tmp_meta, backup_meta)
      end
    end

    `tar cvf - --listed-incremental=#{backup_meta} #{backup} #{exclude_list} | gpg --batch --yes --passphrase "#{@passphrase}" --symmetric --force-mdc -o #{backup_tar}`
    b2_upload_file(backup_tar, backup_tar_remote)

    File.delete(backup_meta_gpg) if File.exists?(backup_meta_gpg)

    encrypt_file(backup_meta, backup_meta_gpg)

    b2_delete_files(b2_list_files(backup_meta_remote))
    b2_upload_file(backup_meta_gpg, backup_meta_remote)

    File.delete(backup_tar)
  else
    puts "Backup #{backup_tar} already exists, skipping"
  end
end

def create_backups(backup_targets)
  backup_targets.each do |target, info|
    if !info.nil? && info.has_key?('exclude')
      create_backup(target, info['exclude'])
    else
      create_backup(target)
    end
  end
end

b2_auth_retry
create_backups(config['backup_targets'])
clean_old_backups if config['clean_old_backups']
