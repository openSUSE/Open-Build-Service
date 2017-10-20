# This is just a thin layer on top of the frontend container
# that makes sure different users can run it without the
# contained rails app generating files in the git checkout with
# some strange user...

FROM openbuildservice/frontend-base
ARG CONTAINER_USERID

# Configure our user
RUN usermod -u $CONTAINER_USERID frontend

ADD src/api/Gemfile /obs/src/api/Gemfile
ADD src/api/Gemfile.lock /obs/src/api/Gemfile.lock
RUN chown -R frontend /obs/src/api

# Now do the rest as the user with the same ID as the user who
# builds this container
USER frontend
WORKDIR /obs/src/api

# FIXME: Retrying bundler if it fails is a workaround for https://github.com/moby/moby/issues/783
#        which seems to happen on openSUSE (< Tumbleweed 20171001)...
RUN export NOKOGIRI_USE_SYSTEM_LIBRARIES=1; bundle install --jobs=3 --retry=3 || bundle install --jobs=3 --retry=3

# Run our command
CMD ["foreman", "start", "-f", "Procfile"] 
