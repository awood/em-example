require 'rack/static'

use Rack::Static, :urls => ["/test.html"], :root => 'content'

run lambda { |env|
  [
    200,
    {
      'Content-Type'  => 'text/html',
      'Cache-Control' => 'public, max-age=86400'
    },
    File.open('content/test.html', File::RDONLY)
  ]
}
