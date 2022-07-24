FROM 'ruby:3.1.0'

COPY . /app

WORKDIR /app

RUN bundle

CMD ["ruby", "src/server.rb"]