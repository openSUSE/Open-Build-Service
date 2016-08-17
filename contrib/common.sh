#!/bin/bash 

function allow_vendor_change() {
  echo 'solver.allowVendorChange = true' >> /etc/zypp/zypp.conf
}

function add_common_repos() {
  zypper -q ar -f http://download.opensuse.org/repositories/devel:/languages:/perl/openSUSE_Leap_42.1/devel:languages:perl.repo
  zypper -q ar -f http://download.opensuse.org/repositories/OBS:/Server:/Unstable/openSUSE_42.1/OBS:Server:Unstable.repo
  zypper -q --gpg-auto-import-keys refresh
}

function install_common_packages() {
  echo -e "\ninstalling required software packages...\n"
  zypper -q -n install --replacefiles\
    update-alternatives make gcc gcc-c++ patch cyrus-sasl-devel openldap2-devel \
    libmysqld-devel libxml2-devel zlib-devel libxslt-devel nodejs mariadb memcached \
    sphinx phantomjs \
    screen \
    ruby2.3-devel \
    ruby2.3-rubygem-bundler \
    ruby2.3-rubygem-mysql2 \
    ruby2.3-rubygem-nokogiri \
    ruby2.3-rubygem-multi_json \
    ruby2.3-rubygem-ruby-ldap \
    ruby2.3-rubygem-xmlhash \
    ruby2.3-rubygem-thinking-sphinx\
    perl-GD \
    perl-XML-Parser \
    perl-Devel-Cover \
    obs-server \
    perl-BSSolv \
    perl-Socket-MsgHdr \
    perl-JSON-XS \
    curl \
    vim-data \
    psmisc \

  # This is a workaround for a very strange behavior
  # After installing one of the follwing packages - obs-server, curl or vim-data
  # grub installation is broken, if we don`t re-install grub, the VM will hang
  # on reboot
  grub2-install /dev/sda
}

function setup_ruby() {
  echo -e "\nsetup ruby binaries...\n"
  [ -f /usr/bin/ruby ] ||ln -s /usr/bin/ruby.ruby2.3 /usr/bin/ruby
  for bin in rake rdoc ri; do
     /usr/sbin/update-alternatives --set $bin /usr/bin/$bin.ruby.ruby2.3
  done
}

function setup_ruby_gem() {
  echo -e "\ndisabling versioned gem binary names...\n"
  echo 'install: --no-format-executable' >> /etc/gemrc
}

function install_bundler_package() {
  echo -e "\ninstalling bundler...\n"
  gem install bundler
}

function install_bundle() {
  echo -e "\ninstalling your bundle...\n"
  su - vagrant -c "cd /vagrant/src/api/; bundle install --quiet"
}

function setup_mariadb() {
  echo -e "\nsetting up mariadb...\n"
  systemctl start mysql
  systemctl enable mysql
  mysqladmin -u root password 'opensuse' 
}

function setup_memcached() {
  echo -e "\nsetting up memcached...\n"
  systemctl start memcached
  systemctl enable memcached
}

function configure_app() {
  if [ ! -f /vagrant/src/api/config/options.yml ] && [ -f /vagrant/src/api/config/options.yml.example ]; then
    cp /vagrant/src/api/config/options.yml.example /vagrant/src/api/config/options.yml
  fi
}

function configure_database() {
  # Configure the database if it isn't
  found=0
  dbs=($(echo "show databases" | mysql -u root --password=opensuse))
  for db in "${dbs[@]}"
    do 
      if [[ $db =~ api_development ]]; then
        echo -e "Already have api_development db...\n"
        set $found=1
        break
      fi  
    done
  if [ $found -eq 0 ]; then
    echo -e "No database found. Will run setup...\n"
    export DATABASE_URL="mysql2://root:opensuse@localhost/api_development"
    cd /vagrant/src/api
    rake -f /vagrant/src/api/Rakefile db:create
    rake -f /vagrant/src/api/Rakefile db:setup
    rake -f /vagrant/src/api/Rakefile test:unit/watched_project_test
    cd -
  else
    echo -e "You already have a database. Skipping this step.\n"
  fi
}

function _prepare_bound_directory() {

  DIRNAMEEXT=$1
  TMP_DIR=/tmp/vagrant_$1
  MOUNT_DIR=/vagrant/src/api/$1
  for dir in $MOUNT_DIR $TMP_DIR
  do
    if [ ! -d $dir ];then
      echo " - Creating directory $dir"
      mkdir -p $dir
      chown vagrant:users $dir
    fi 
  done

  # create log files to ensure they are owned by vagrant
  if [ "$1" == "log" ];then
    for log in backend_access.log  development.log  test.log
    do
      touch $TMP_DIR/$log
    done
  fi

  chown vagrant:users -R $TMP_DIR

  TMP_IN_FSTAB=$(grep "$MOUNT_DIR" /etc/fstab)
  if [ -z "$TMP_IN_FSTAB" ];then
    echo " - Adding $TMP_DIR to fstab"
    echo -e "$TMP_DIR $MOUNT_DIR none bind 0 0" >> /etc/fstab
  fi

}

function setup_data_dir() {
  echo "Generating data dir and mounting them So hard links can be used..."
  # Put the backend data dir outside the shared folder so it can use hardlinks
  # which isn't possible with VirtualBox shared folders...
  _prepare_bound_directory tmp
  _prepare_bound_directory log
  mount -a

}



function print_final_information() {
  echo -e "\nProvisioning of your OBS API rails app done!"
  echo -e "To start your development OBS backend run: vagrant exec contrib/load_dev_backend.sh\n"
  echo -e "To start your development OBS frontend run: vagrant exec rails s\n"
  echo -e "\nTo start testing : \nvagrant ssh\n";
  echo -e "\nmake -C /vagrant/src/api test\n";
}

function chown_vagrant_owned_dirs() {

  BASE_DIR=/vagrant/src/api/
  # create log files to ensure they are owned by vagrant
    for dir in log tmp
    do
      chown -R vagrant:users $BASE_DIR/$dir
    done

}

function prepare_apache2 {

  echo -e "\nPreparing apache setup\n"

  PACKAGES="apache2 apache2-mod_xforward rubygem-passenger-apache2 memcached"
  PKG2INST=""
  for pkg in $PACKAGES;do
    rpm -q $pkg >/dev/null || PKG2INST="$PKG2INST $pkg"
  done

  if [[ -n $PKG2INST ]];then
    zypper --non-interactive install $PKG2INST >/dev/null
  fi

  MODULES="passenger rewrite proxy proxy_http xforward headers socache_shmcb"

  for mod in $MODULES;do
    a2enmod -q $mod || a2enmod $mod
  done

  FLAGS=SSL

  for flag in $FLAGS;do
    a2enflag $flag >/dev/null
  done

  systemctl enable apache2.service
}

