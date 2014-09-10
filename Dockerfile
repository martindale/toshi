# Start with ruby-2.1.2
FROM ruby:2.1.2

# Install dependencies
RUN gem install bundler

# Add the Gemfile to the image
# Separate this from the source so as not to bust the cache
ADD Gemfile /Gemfile
ADD Gemfile.lock /Gemfile.lock

# Install gems
RUN bundle install

# Add the source dir
ADD . /toshi

# Set up our working dir
WORKDIR /toshi

# Expose port 5000 of the container to the host
EXPOSE 5000

# Start Toshi
CMD ["bundle", "exec", "foreman", "start"]
