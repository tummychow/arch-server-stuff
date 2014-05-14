# Part 3: Phabricator

[<- Part 2](../part2) | [Part 4 ->](../part4)

This part covers:

- installing the dependencies for Phabricator (MySQL and PHP)
- installing Phabricator itself and hosting it with nginx
- configuring Phabricator's basic functions
- setting up Phabricator repository hosting with Git over ssh

## Step 1: Phabricator Dependencies

Phabricator is a pretty traditional PHP web application - it uses MySQL as its database backend, and either Apache with mod_php or nginx with php-fpm. Obviously this guide uses the latter. [Another guide](http://therning.org/magnus/archives/1135) uses lighttpd, but you might want to read it anyway because it's a useful resource (I referred to it often while writing this part). Install dependencies first:

```bash
# mariadb: Arch Linux's MySQL implementation
# php-fpm: the PHP FastCGI server used by nginx
# php et al: PHP itself, plus some important extensions
$ pacman -S mariadb php-fpm php php-cgi php-apcu php-gd
```

You have to do some initial configuration for MariaDB:

```bash
$ systemctl start mysqld
$ mysql_secure_installation
$ systemctl stop mysqld
```

You can read more about the configuration script [here](https://mariadb.com/kb/en/mysql_secure_installation/). Press enter first (the script wants the database's root password, but you just installed MariaDB, so there is no root password). The rest is up to you. I pressed N next (don't use a root password) and I pressed Y for all the other questions. Obviously this is *not* a secure configuration, but that's not too important for me.

Next, you need to enable the PHP extensions you installed. PHP's configuration is `/etc/php/php.ini`. The extension lines are of the form `;extension=foobarbaz.so`. The semicolon indicates a comment. Make sure the following extensions are enabled (uncomment them if they're already present, add them to the list otherwise):

- apcu.so
- gd.so
- iconv.so
- mysqli.so
- openssl.so
- posix.so

There's another important setting in this file, `open_basedir`. Basically, this setting says that PHP can only access files under a certain list of directories. This setting is enabled by default on Arch Linux, so I just commented it out.

You also need to configure php-fpm (the config file is `/etc/php/php-fpm.conf`). First, you have to set the user that php-fpm will run as. Look for the line `[www]`, and not too far below that, you should find a line `user = http`. Set it to the name of your unprivileged user. Not too far from this, you'll find another line that says `listen = unix:/run/php-fpm/php-fpm.sock`. By default, this is enabled; leave it that way. There is also a line `listen = 127.0.0.1:9000` which is commented - again, leave it that way. These listen lines control where php-fpm listens for requests from the webserver. By default, it's using a Unix socket, which is a bit faster than TCP ports. You need to make sure that the php-fpm user has access to the socket as well. Find the `listen.owner` line, and set it to peon. The `listen.mode` is set to 660 by default, which is fine.

## Step 2: Installing Phabricator

Now PHP is set up for Phabricator, and you need to acquire Phabricator itself. I recommend you switch to the unprivileged user at this point. The installation process is basically three git clones (upgrading is a git pull). I'm going to clone them to `/home/peon/phabroot`. (If you didn't install Gollum, you will need to install git at this point, or download tarballs from GitHub instead of cloning.)

```bash
$ mkdir phabroot && cd phabroot
$ git clone git://github.com/facebook/libphutil.git
$ git clone git://github.com/facebook/arcanist.git
$ git clone git://github.com/facebook/phabricator.git
```

There's also some initial configuration you can do while you're here. Phabricator provides several scripts in `phabricator/bin` for maintaining your Phabricator instance. The database settings are the easiest to set up and you can turn them on right away. Phabricator tries to access the database using the user `root`, with no password, by default. That's what I was using, so I didn't need to change any configurations, but if you set a password (or if you want Phabricator to use another user), you'll need to change it.

```bash
$ cd phabricator
$ bin/config set mysql.user root # mysql root user
$ bin/config set mysql.pass '' # mysql root password
# start mysqld if it's not running
$ bin/storage upgrade --user root
```

Now, you need to add nginx configuration for phabricator. Here is the server block:

```nginx
server {
    server_name 127.0.0.1;
    listen 81;

    root /home/peon/phabroot/phabricator/webroot;
    try_files $uri $uri/ /index.php

    location / {
        index index.php;
        if ( !-f $request_filename ) {
            rewrite ^/(.*)$ /index.php?__path__=/$1 last;
            break;
        }
    }

    location /index.php {
        fastcgi_pass unix:/run/php-fpm/php-fpm.sock;
        fastcgi_index index.php;
        include fastcgi.conf;
    }
}
```

Note that the port is set to 81. If you already set up Gollum, then it's using 127.0.0.1:80. You can't have both servers listening on the same hostname and the same port. nginx wouldn't know which one to serve. So the ports have to be different. Once that's done, you need to start mysqld, php-fpm and nginx: `systemctl start mysqld php-fpm nginx`.

Now, you can navigate to `localhost.localdomain:81` to get started. Note that Phabricator needs to run on a fully qualified domain name (FQDN), with a DNS suffix (that's the `.com` at the end of `github.com`). That's why you need to use `localhost.localdomain` and not just `localhost` or 127.0.0.1. [Part 4](PART4.md) discusses how to set up an FQDN using your router.

## Step 3: Phabricator Configuration Details

It's a credit to the Phabricator team that their software explains itself so well. You should be able to figure out most of the setup issues just from reading over the setup issues. Some of those issues are more interesting than others.

For the Phabricator daemons, they are managed through the `phd` script in `phabricator/bin`. I wrapped the script in a very simple [systemd unit](phd.service), which is included with this repository. Add this unit to `/etc/systemd/system/`, and then you can control the daemons from systemd with `systemctl start phd` and `systemctl stop phd`.

When you configure the Phabricator repository root, remember that this directory needs to be accessible by the Phabricator daemons. The systemd unit runs the daemons as peon, so the repository root also needs to be accessible to the user peon. I used a local directory, and set it like so:

```bash
$ bin/config set repository.default-local-path "/home/peon/phabroot/repo"
```

The base-uri should be set to the FQDN you want to run Phabricator on, plus the `http://` at the start. You can also leave it unset and serve Phabricator at any domain that maps to it.

Some of the configurations will require root. To turn on strict mode for MariaDB, you need to find `[mysqld]` in `/etc/mysql/my.cnf` and add the line `sql_mode = STRICT_ALL_TABLES`. Then you can `systemctl restart mysqld` to load the new configuration. You'll also need to set a PHP timezone, which can be found under `date.timezone` in `/etc/php/php.ini`. I set it to `Canada/Eastern`, but you probably want to use your own timezone.

The most interesting configuration option is the mail backend. Phabricator can send mail to users for notifications, but it needs a service to provide the delivery. Phabricator supports several paid services (Amazon SES, Mailgun) which make this process easy, but they cost money. The default mail adapter invokes the `sendmail` binary. This is a *de facto* standard from the days of the first popular mail transfer agent, sendmail. Nowadays, the most popular MTA is probably postfix. Arch has official packages for postfix and exim, both of which provide the `sendmail` binary. I'll go into more details on those in another section.

## Step 4: Phabricator Repo Hosting

Phabricator has a great guide [here](https://secure.phabricator.com/book/phabricator/article/diffusion_hosting/) which will be useful throughout this part. I'm only interested in ssh hosting, so I'll ignore the parts about HTTP. It mentions having multiple different users for the daemons, the webserver, and the repository user, but for convenience, all three users will be the same: peon. The daemons are already run by peon, and the nginx workers are already running under peon, so the next step is setting up peon to be the repository user. You also don't have to worry about the webserver user (the nginx worker user) if you're not using HTTP access.

Phabricator needs the other users to be able to sudo as the repository user. This is true *even* if all three users are the same. (Yes, peon needs to be able to sudo as peon.) I didn't have peon configured for *any* sudo permissions, at all, so I had to add the permissions that Phabricator wanted. Crack open `visudo` with your preferred editor (eg `EDITOR=nano visudo`) and add this line at the bottom:

```
peon ALL=(peon) SETENV: NOPASSWD: /usr/bin/git-upload-pack, /usr/bin/git-receive-pack, /usr/bin/hg, /usr/bin/svnserve
```

Then, run the following configuration commands. In my case, peon has no password, so I didn't need to run any password modification commands. (I found that doing things like `passwd -l peon` or `usermod -e 1970-01-01 peon` broke my configuration. Phabricator recommends doing things like editing `/etc/shadow` but I'd *really* rather do that using standard passwd commands. Your mileage may vary.)

```bash
$ bin/config set phd.user peon
$ bin/config set diffusion.ssh-user peon
```

Next, you need to move sshd to another port. Phabricator will run another instance of sshd on port 22, which will be restricted for repository access only, so your real sshd instance needs to go somewhere else. In `/etc/ssh/sshd_config`, change the `Port` to another one that you'll remember. The documentation is very careful about this step, because if your only access is over ssh, you could lock yourself out of the server. I'm pretty careless about this since I can either drop into the virtual console directly (VM) or access the system's hardware serial console (ARM computers). Many of the big VPS hosters have a web interface to access your machine's virtual console. That might also be useful. Once you've updated the sshd configs, `systemctl restart sshd`. Exit and try sshing into the new port: `ssh root@yourhost -p yourport`. If you did things right, that should actually work. Now you can continue. (If you're using scp to copy into the server, the flag for the port is `-P`. That's a capital P.)

There are two Phabricator sshd configuration files in `/home/peon/phabroot/phabricator/resources/sshd` (or similar for you). I copied the custom sshd config to `/etc/ssh/phab_sshd_config`, and I copied the script to `/etc/ssh/phabricator-ssh-hook.sh`. Make sure to edit both files. You need to set the name of the VCS user (in my case, peon), the authorized command (the location of the Phabricator ssh script), and the location of Phabricator itself (ie `/home/peon/phabroot/phabricator`). I also changed the sshd config's `PidFile` to `/run/sshd-phabricator.pid`. Assuming your config is in the same places as mine, you can use my systemd unit, [sshd-phab](sshd-phab.service), to launch the custom sshd.

Launch all your daemons - mysqld, php-fpm, phd, nginx and the new sshd (in my case, sshd-phab). Log into your Phabricator instance and navigate to Settings->SSH Public Keys->Upload. Add a public key for the system you're currently on (ie the one you're using to ssh into the server). Now, go back to that system, and try the following commands:

```bash
$ echo {} | ssh peon@phab.lan conduit conduit.ping
{"result":"SEKHMET","error_code":null,"error_info":null}
# note: SEKHMET is the actual hostname of my server, in /etc/hostname
# yours will probably be different

$ ssh peon@phab.lan
PTY allocation request failed on channel 0
phabricator-ssh-exec: Welcome to Phabricator.

You are logged in as sjung.

You haven't specified a command to run. This means you're requesting an interactive shell, but Phabricator does not provide an interactive shell over SSH.

Usually, you should run a command like `git clone` or `hg push` rather than connecting directly with SSH.

Supported commands are: conduit, git-receive-pack, git-upload-pack, hg, svnserve.
Connection to phab.lan closed.
```

As you can see, your login is denied (which is good, because people should not be able to login as the VCS user), and you get some nice pretty Phabricator messages to indicate that your public key is where it's supposed to be. If this part isn't working, then you didn't configure your sshd correctly, or your VCS user's login permissions are messed up.

Once this is all done, I recommend trying to add a new repo to your Phabricator instance. You'll need to go into the advanced options and ensure that ssh access to the repo is enabled. Then activate the repo. If you head to the repo's root (eg `http://phab.lan/diffusion/S/` if the callsign is S), you should see an ssh clone URL. This indicates that Phabricator has been configured to provide this repo over ssh.

Add the ssh remote URL to an existing Git repository you have, and try pushing to it. If everything goes off without a hitch, you should be able to see the repository contents on your Phabricator instance. If that *didn't* work, then your sudoers configuration is probably the issue - it indicates that you can ssh in under peon, but peon does not have the authority to run the commands required.

[<- Part 2](../part2) | [Part 4 ->](../part4)
