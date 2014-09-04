# Start with an Ubuntu 14.04 image that has ruby 2.1.2
FROM litaio/ruby:2.1.2

# Install dependencies
RUN apt-get -y install libpq-dev
RUN gem install bundler

# Add the Gemfile to the image
# Separate this from the source so as not to bust the cache
ADD Gemfile /Gemfile
ADD Gemfile.lock /Gemfile.lock

# Install gems
RUN bundle install 

# Add the source dir
ADD . /toshi

# Copy the config template
ADD config/toshi.yml.example /toshi/config/toshi.yml

# Set up our working dir
WORKDIR /toshi

# Expose port 5000 of the container to the host
EXPOSE 5000
