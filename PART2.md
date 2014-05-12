# Part 2: Gollum

[<- Part 1](PART1.md) | [Part 3 ->](PART3.md)

This part covers:

- installing Gollum and its dependencies
- configuring Gollum to be served by nginx, using Passenger
- alternatively, configuring Gollum to be served by Unicorn, with nginx as a reverse proxy

## Step 1: Installing Gollum

The next step is to get [Gollum](https://github.com/gollum/gollum). Gollum has a few non-Ruby dependencies. One of Gollum's gems, [charlock_holmes](https://github.com/brianmario/charlock_holmes) links to icu (International Components for Unicode). Another gem, [nokogiri](http://nokogiri.org), requires libxml2 and libxslt. (I'm not sure if nokogiri requires the system libraries, so you might be able to skip this.) Finally, Gollum's Git access is powered by the git binary. So you need all of those:

```bash
$ pacman -S icu libxml2 libxslt git
```

Gollum used to do syntax highlighting with [Pygments](https://github.com/tmm1/Pygments.rb), a Python library that it invoked from Ruby via process spawning. Nowadays, Gollum uses [Rouge](https://github.com/jneen/rouge), which is pure Ruby, so you don't need to install Pygments. If you want to use Pygments anyway, you will need to install the official `python2-pygments` package (or get `pygmentize`, the Pygments script, onto your PATH in some way). The official `python-pygments` package uses Python 3 instead of 2, but it doesn't put the `pygmentize` script onto your PATH (have to add it yourself). Anyway, all this is irrelevant because Rouge is easier to work with.

Now you can install Gollum. This repository contains a [`config.ru`](config.ru) which configures Rack-compatible servers to host Gollum, and a [`Gemfile`](Gemfile) which identifies Gollum's dependencies for this environment. I run Gollum with very few dependencies because I speak Markdown almost exclusively, but Gollum is a polyglot and can support other markup languages if you so choose. Just add them to the Gemfile so that Gollum knows how to parse them. (Gollum depends on Rouge out of the box, so you don't need to add that to the Gemfile.)

Anyway you need to acquire these two files and put them somewhere good. I store them under peon's home directory, in `/home/peon/gollum`. peon needs to own these files, so I do this part as peon.

To use the Gemfile we need bundler. I'm going to install bundler by hand (instead of using the AUR package), but anything that gets `bundle` onto your PATH will work.

```bash
# make sure gems are installed locally
$ export GEM_HOME=$(ruby -e 'puts Gem.user_dir')
# add gems to the path
$ export PATH="/home/peon/.gem/ruby/2.1.0/bin:$PATH"
$ gem install bundler
$ cd /home/peon/gollum && bundle install # acquire gems
```

There are a few more things that must be done before Passenger can serve Gollum. It needs `public` and `tmp` dirs underneath `/home/peon/gollum`. So let's make those:

```bash
$ mkdir tmp public
```

In addition, remember that Gollum is a wiki backed by a Git repository. You need to instantiate the Git repository where Gollum expects it. My `config.ru` sets the repository directory to `/home/peon/gollum/repo`, so do this as well:

```bash
$ mkdir repo && cd repo
$ git init
```

## Step 2: Configuring nginx and Passenger

This nginx build is compiled with Passenger, but you have to set some directives telling nginx where to find Passenger's extra stuff. The nginx-passenger PKGBUILD places these files at `/usr/lib/passenger`. You also need to tell Passenger where to find Ruby, since it needs to use Ruby to host Gollum. The system Ruby binary is located at `/usr/bin/ruby`. (If you installed Ruby separately, you'll need the path to the Ruby binary, wherever it is.) These locations correspond to the `passenger_root` and `passenger_ruby` directives, respectively. Generally, you will only use one Ruby for all of Passenger, so you can set these directives in the `http` block:

```nginx
http {
    # ...
    passenger_root /usr/lib/passenger;
    passenger_ruby /usr/bin/ruby;
    # ...
}
```

Now, nginx needs to know which applications will be using Passenger. You do this by adding a `passenger_enabled on;` directive to the server block. Passenger expects that the root directory of the server will be that empty `public` directory we made earlier. So the server configuration should look vaguely like this:

```nginx
server {
    server_name 127.0.0.1;
    listen 80;
    root /home/peon/gollum/public;
    passenger_enabled on;
}
```

And that's all! If you start nginx, gollum should come up at the port and path you specified. The Gollum wiki will store its repository is at `/home/peon/gollum/repo`, as I mentioned earlier. You can edit those files with any text editor and the changes will appear in Gollum's hosted content.

You should be aware that this configuration is probably suboptimal. Gollum contains, inside the gem, its public assets (CSS, JS and so on). Ideally, we'd rather serve these assets through nginx without indirecting through Passenger and Gollum itself. That makes installation more complicated (because you have to install your repository and config files inside Gollum's own gem directory), and it's not a big deal for me, so I don't care to figure out a fix.

## Step 3: Configuring Unicorn

Although this guide uses Passenger (and in general, I stick to Passenger), I saw some value in experimenting with [Unicorn](http://unicorn.bogomips.org) as well. After all, this entire thing is a learning experience for me, so might as well screw around. I chose to use Unicorn because it is probably the most popular production Rack server besides Passenger. I'm not experienced enough to summarize the architectural differences between the various Rack servers, so I won't go into the details here.

Acquiring Unicorn for your environment is simple: add it to the Gemfile, then `bundle install` again to pull it down. I couldn't install kgio (one of Unicorn's dependencies) without root, so I switched back to root and invoked `gem install --no-user-install unicorn` first.

```ruby
gem 'unicorn', '~> 4.8.3'
```

To launch the Unicorn master, you simply `unicorn` from the directory containing your `config.ru`, like so:

```bash
$ cd /home/peon/gollum
$ bundle exec unicorn -D -l /run/unicorn/gollum.sock
```

This is technically enough to launch Unicorn's workers, listening on the socket `unix:/run/unicorn/gollum.sock`. Important note: each Unicorn master can only serve one application, where as Passenger can serve many applications (and, under some circumstances, share memory between them, eg if they all use the same version of Rails). Then configure an nginx reverse proxy to the workers like so:

```nginx
upstream gollum_unicorn {
  server unix:/home/peon/gollum/tmp/gollum.sock fail_timeout=0;
}

server {
    server_name 127.0.0.1;
    listen 80;
    root /home/peon/gollum/public;

    location / {
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Host $http_host;
        proxy_redirect off;

        proxy_pass http://gollum_unicorn;
    }
}
```

However, I recommend, and have provided, a suitable `unicorn.rb` and a systemd unit file to go with it. You can `systemd start unicorn.gollum` with this setup. Again, remember that each application needs its own master process and its own socket. We configure some important files (notably the PID file and the socket location) in the config file, so each master process will also need its own config file. As far as configuration goes, Passenger is clearly easier. Remember to clean out the `gollum/tmp` directory if you switch back to the Passenger configuration (that's where my configuration of Unicorn puts all the logs and sockets, so it might be a bit cluttered).

[<- Part 1](PART1.md) | [Part 3 ->](PART3.md)
