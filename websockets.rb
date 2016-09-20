#! /usr/bin/env ruby

require "json"
require "em-websocket"
require "http/parser"

module Commands
  class Serve
    # The LiveReload protocol requires the server to serve livereload.js over HTTP
    # despite the fact that the protocol itself uses WebSockets.  This custom connection
    # class addresses the dual protocols that the server needs to understand.
    class HttpAwareConnection < EventMachine::WebSocket::Connection
      attr_reader :reload_body, :reload_size

      def initialize(opts)
        em_opts = {}
        # This is too noisy even for --verbose, but uncomment if you need it for
        # a specific WebSockets issue.  Adding ?LR-verbose=true onto the URL will
        # enable logging on the client side.
        # em_opts[:debug] = true

        super(em_opts)

        reload_file = File.join('content', "livereload.js")

        @reload_body = File.read(reload_file)
        @reload_size = File.size(reload_file)
      end

      # rubocop:disable Metrics/MethodLength
      # rubocop:disable Metrics/AbcSize
      def dispatch(data)
        parser = Http::Parser.new
        parser << data

        # WebSockets requests will have a Connection: Upgrade header
        if parser.http_method != "GET" || parser.upgrade?
          super
        elsif parser.request_url =~ %r!^\/livereload.js!
          headers = [
            "HTTP/1.1 200 OK",
            "Content-Type: application/javascript",
            "Content-Length: #{reload_size}",
            "",
            ""
          ].join("\r\n")
          send_data(headers)

          # stream_file_data would free us from keeping livereload.js in memory
          # but JRuby blocks on that call and never returns
          send_data(reload_body)
          close_connection_after_writing
        else
          body = "This port only serves livereload.js over HTTP.\n"
          headers = [
            "HTTP/1.1 400 Bad Request",
            "Content-Type: text/plain",
            "Content-Length: #{body.bytesize}",
            "",
            ""
          ].join("\r\n")
          send_data(headers)
          send_data(body)
          close_connection_after_writing
        end
      end
    end

    class LiveReloadReactor
      def initialize(threaded=false)
        puts("Threaded mode? #{threaded}")
        @threaded = threaded
        @websockets = []
        @connections_count = 0

        @start_proc = Proc.new do |opts|
          # Use epoll if the kernel supports it
          EM.epoll
          EM.run do
            EM.error_handler do |e|
              log_error(e)
            end
            puts("Running")

            unless @threaded
              EM.add_periodic_timer(5) do
                reload(["/test.html"])
              end
            end

            EM.start_server(
              opts["host"],
              opts["livereload_port"],
              HttpAwareConnection,
              opts
            ) do |ws|

              ws.onopen do |handshake|
                connect(ws, handshake)
              end

              ws.onclose do
                disconnect(ws)
              end

              ws.onmessage do |msg|
                print_message(msg)
              end

              ws.onerror do |error|
                log_error(error)
              end
            end
          end
        end
      end

      def stop
        # There is only one EventMachine instance per Ruby process so stopping
        # it here will stop the reactor thread we have running.
        EM.stop if EM.reactor_running?
        puts("LiveReload Server: halted")
      end

      def start(opts)
        if @threaded
          @thread = Thread.new do
            @start_proc.call(opts)
          end
        else
          @start_proc.call(opts)
        end
      end

      # For a description of the protocol see
      # http://feedback.livereload.com/knowledgebase/articles/86174-livereload-protocol
      def reload(pages)
        pages.each do |p|
          msg = {
            :command => "reload",
            :path    => p,
            :liveCSS => true
          }

          puts("Reloading #{p}")
          puts(JSON.dump(msg))
          @websockets.each do |ws|
            ws.send(JSON.dump(msg))
          end
        end
      end

      private
      def connect(ws, handshake)
        @connections_count += 1
        if @connections_count == 1
          puts("Browser connected")
        end
        ws.send(
          JSON.dump(
            :command    => "hello",
            :protocols  => ["http://livereload.com/protocols/official-7"],
            :serverName => "jekyll"
          )
        )

        @websockets << ws
      end

      private
      def disconnect(ws)
        @websockets.delete(ws)
      end

      private
      def print_message(json_message)
        msg = JSON.parse(json_message)
        # Not sure what the 'url' command even does in LiveReload.  The spec is silent
        # on its purpose.
        if msg["command"] == "url"
          puts("#{msg["url"]}")
        end
      end

      private
      def log_error(e)
        puts("LiveReload Error: #{e.message}")
        puts("#{e.backtrace.join("\n")}")
      end
    end
  end
end

threaded = (ARGV.first == "threaded")

reactor = Commands::Serve::LiveReloadReactor.new(threaded)
reactor.start("livereload_port" => 35729, "host" => "127.0.0.1")

trap("SIGINT") do
  reactor.stop
  exit
end

if threaded
  loop do
    sleep 5
    reactor.reload(["/test.html"])
  end
end
