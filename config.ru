#!/usr/bin/env ruby

require 'rubygems'
require 'bundler/setup'
require 'gollum/app'

# path to the Gollum repository
# set to: the subdirectory repo, under the location of this file
gollum_path = File.expand_path(File.dirname(__FILE__)) + '/repo'
Precious::App.set(:gollum_path, gollum_path)

Precious::App.set(:default_markup, :markdown)

# set gollum options
# anything that can be set on the command line can also be set here
# see https://github.com/gollum/gollum/blob/master/bin/gollum
# and https://github.com/gollum/gollum-lib/blob/master/lib/gollum-lib/wiki.rb#L164
Precious::App.set(:wiki_options, {
  # table of contents on every page?
  :universal_toc => false,
  # live preview for gollum's embedded ace editor? (this can be slow)
  :live_preview => false,
  # enable mathjax embedding for text wrapped in \\(\\) ?
  :mathjax => false,
  # show files in the tree view even if they don't correspond to pages of the wiki?
  :show_all => false,
  # collapse the file tree view by default?
  :collapse_tree => false,
  # set the title of every page to its first h1-level heading?
  :h1_title => true,
  # use this ref in the gollum_path repo for hosting?
  :ref => 'master'
})

run Precious::App
