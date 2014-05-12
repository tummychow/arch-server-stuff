# Part 1: General Requirements

[<- Readme](README.md) [Part 2 ->](PART2.md)

This part covers:

- setting up sshd for remote access. This is particularly important for Phabricator repository hosting.
- installing nginx with Phusion Passenger, to natively host Ruby Rack applications.
- adding an unprivileged user for serving content.

## Step 1: sshd

First up: if you don't know what ssh is, [go here](https://wiki.archlinux.org/index.php/Secure%20Shell). My server is headless, as most production servers are, so I like to edit configs and stuff from my main system, which is more comfortable. You need ssh for that. ssh is also important for manipulating Git repositories hosted by Phabricator, so if you plan on using Phabricator, this step is especially important.

Your fresh Arch system will not have ssh out of the box, so you need to install it first. I have no familiarity with alternative SSH servers like dropbear, so if you use those you're on your own.

```bash
$ pacman -S openssh
```

The configs for sshd are in `/etc/ssh/sshd_config`. I like the default configuration for Arch, so I don't have to do much to it. You'll need root access fairly frequently throughout this guide, so I recommend leaving root logins enabled. Of course, you could also set up a user with sudo to do that heavy lifting. (If your root has no password because you're *really* careless about security, like me, then you will need to enable `PermitEmptyPasswords` as well.) I'd also recommend logging in once with a password to copy over your public key, and then disabling password authentication, so only keys are allowed. More on ssh keys can be found [here](https://wiki.archlinux.org/index.php/SSH_Keys).

One more thing: don't forget to start sshd. As with most services on Arch, you control it with systemctl. `systemctl start sshd` for just this session, and `systemctl enable sshd` to start it every time you boot. `systemctl stop sshd` to turn it off, and `systemctl disable sshd` to prevent it from starting on boot.

## Step 2: nginx

Arch Linux has a great standard [package](https://www.archlinux.org/packages/extra/x86_64/nginx/) for nginx. If you only need to host Phabricator, or if you plan to host Gollum using Unicorn (which I will cover), you can use this package and skip this entire section:

```bash
$ pacman -S nginx
```

However, for our purposes, the official package can't be used (so don't install it). You also need Phusion Passenger. [Passenger](https://www.phusionpassenger.com) is a module for Apache and nginx, which allows those webservers to natively serve web applications written in various interpreted languages (notably Ruby with Rack and Python with WSGI). We are going to use Passenger to host Gollum. I am also experimenting with Apache Bloodhound and I plan to host that with Passenger as well. nginx does not load modules dynamically, so you have to recompile it with Passenger built in. There are some useful instructions [here](http://www.modrails.com/documentation/Users%20guide%20Nginx.html#_installing_as_a_normal_nginx_module_without_using_the_installer).

Luckily this is Arch Linux, and we have an excellent toolchain to support unofficial packages. For this application, you'll need the [nginx-passenger](https://aur.archlinux.org/packages/nginx-passenger/) AUR package. It's got everything the official package does, plus Passenger. First, you need to acquire some dependencies. Passenger uses Ruby scripts during build, configuration and for some [internal operations](http://www.modrails.com/documentation/Users%20guide%20Nginx.html#relationship_with_ruby), so you'll need that first. Passenger's use of Ruby also requires the Rack gem, so you'll need that as well.

```bash
$ pacman -S ruby ruby-rack
```

I use [chruby](https://github.com/postmodern/chruby) in development, so I normally don't install the official Ruby package. However, for production environments, it may be beneficial to avoid a Ruby switcher and stick to one Ruby for the whole system. Passenger can play nicely with RVM, but some applications, like GitLab, explicitly warn against the use of Ruby switchers. If you disagree and want to use a Ruby switcher, that's fine. Install Ruby and the Rack gem however you prefer.

Next, you need to build nginx-passenger. Arch makes this nice and straightforward. If you installed Ruby and Rack separately, you'll need to remove those dependencies from the PKGBUILD first. The package will still be dependent on Ruby being in your PATH (and that Ruby needs to have the Rack gem installed), but it won't complain about the pacman packages for those things being missing. I've tried it without difficulty on my system.

**Note**: Always remember to read over the PKGBUILD for an unofficial package, before invoking makepkg on it. A PKGBUILD is an arbitrary bash script and it can mess your system up. Installing untrusted packages is a recipe for disaster. Personally I don't see anything wrong with the nginx-passenger package, but this is good advice for Arch users in general. Just something to remember if this is your first time using the AUR.

```bash
$ curl -kL https://aur.archlinux.org/packages/ng/nginx-passenger/nginx-passenger.tar.gz | tar -xz
$ cd nginx-passenger
$ makepkg # add --asroot if you are using root
$ pacman -U nginx-passenger-1.6.0.pkg.tar.xz
```

One more thing - if you'd rather not install development stuff on your server, you can build the package on another system of the same architecture, and scp it onto your server, then `pacman -U` from there. This can also be helpful if you don't have enough memory to build nginx - I had difficulty compiling this package with 512MB of memory. This is pretty easy if your server is x86. It's a bit more challenging, but hardly impossible, if it's ARM. Cross-compilation for Arch Linux ARM is out of the scope of this guide.

The configuration for nginx is in `/etc/nginx/nginx.conf`. This is not a guide on how to configure nginx, so I'm not going to go into detail on that subject (not to mention I'm pretty inexperienced myself). My [nginx.conf](nginx.nginxconf) has links to some other useful resources. If you're missing the `mime.types` or `fastcgi.conf` files, I recommend you retrieve them from nginx's own [source](http://trac.nginx.org/nginx/browser/nginx/conf). Oh, and sorry about the weird `.nginxconf` extensions - [GitHub's syntax highlighting](https://github.com/github/linguist/blob/master/lib/linguist/languages.yml#L1362) requires it, and my editor also uses the extension to guess the [syntax](https://github.com/brandonwamboldt/sublime-nginx).

As with sshd, you can control nginx with `systemctl start nginx` and so on. You can also ask nginx to reload the configurations with `systemctl reload nginx` (not all services will support this command, but nginx does). The systemd unit file for nginx is included in the AUR package (same as in the official package), so no need to add it yourself.

## Step 3: User Configuration

In order for nginx to serve content, the workers have to be able to read it. If you set the workers to run as root, they can obviously read anything, but that's also bad for security if your server is compromised. The user that serves content to the Internet should be as unprivileged as possible. Often, this user is named `www` or something like that, but I'm going to use one user to run all the unprivileged processes on this server, and I am going to name that user `peon`. Files that need to be served will be installed to various places under peon's home directory, `/home/peon`. In practice, you might want to segment even further and allocate one user for each major service, so that they share as little permission as possible. That's too much work for me, but hey, maybe it's something to look into.

```bash
$ useradd -m -U peon
```

When I install stuff that will be served, I am generally going log into peon, because I'm too lazy to `chown` things to peon after creating them. User permissions in Linux are a pretty big subject, so I'll leave it at that. You should familiarize yourself with the `chmod`, `chmod` `usermod` and `passwd` commands if you want to know more. The `sudo -u peon <command>` and `su - peon` commands might also be helpful (for invoking a command as peon, and becoming peon, respectively).
