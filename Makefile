# Generate a debian package for fluent-plugin-logdna
#
# This assumes that you have the td-agent package already installed
# https://docs.fluentd.org/v1.0/articles/install-by-deb
#
# The package is created with fpm (it does not necessarily need to be
# installed into the td-agent embedded ruby). To install fpm run:
# $ sudo gem install --no-ri --no-rdoc fpm
#
# The td-agent package installs an embedded ruby distribution in
# /opt/td-agent/embedded which has its own list of gems. Our built package
# cannot conflict with those gems so we will elect to bundle a subset of gems
# with our package. This may conflict with other packages and this package is
# not intended to be a general purpose package.

# Paths to td-agent specific versions of bundle and gem
BUNDLE=/opt/td-agent/embedded/bin/bundle
GEM=/opt/td-agent/embedded/bin/gem
RUBY=/opt/td-agent/embedded/bin/ruby
FPM=fpm

# The list of gems to bundle into the final package
BUNDLED_GEMS=unf_ext unf domain_name http-cookie http-form_data http

# Bundle will unpack gems into the bundle directory
BUNDLE_DIR=./vendor/bundle
# Bundle will save gems in the cache directory
CACHE_DIR=./vendor/cache
# Bundle will store settings and locks in the dot_bundle directory
DOT_BUNDLE=./.bundle

GEMSPEC := ${wildcard *.gemspec}
NAME    := ${shell $(RUBY) -e 'puts Gem::Specification::load("$(GEMSPEC)").name'}
VERSION := ${shell $(RUBY) -e 'puts Gem::Specification::load("$(GEMSPEC)").version.to_s'}
GEMFILE := ${shell $(RUBY) -e 'puts Gem::Specification::load("$(GEMSPEC)").file_name'}
DEBFILE := $(NAME)_$(VERSION)_all.deb

$(BUNDLE_DIR): Gemfile.lock
	$(BUNDLE) install --frozen --path $(BUNDLE_DIR)

$(CACHE_DIR): $(BUNDLE_DIR) Gemfile.lock
	$(BUNDLE) package --no-install

TARGETS=${filter $(BUNDLED_GEMS),${wildcard $(CACHE_DIR)/*.gem}}

deps: $(BUNDLE_DIR) $(CACHE_DIR)

gem: $(BUNDLE_DIR) deps
	$(BUNDLE) exec $(GEM) build -V $(GEMSPEC)

deb: gem deps
	$(FPM) --input-type gem --output-type deb \
	  --depends 'td-agent > 2' \
	  --no-auto-depends \
	  --gem-gem $(GEM) \
	  --no-gem-fix-name \
	  --deb-build-depends 'td-agent > 2' \
	  $(TARGETS) $(GEMFILE)

clean:
	rm -rf $(BUNDLE_DIR) $(CACHE_DIR) $(DOT_BUNDLE) $(GEMFILE) $(DEBFILE)

.PHONY: deps gem deb clean
