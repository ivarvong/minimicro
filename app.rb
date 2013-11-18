require 'sinatra/base'
require 'sinatra-websocket'
require 'open-uri'
require 'net/http'
require 'net/https'
require 'redis'
require 'celluloid/autostart'
require 'digest/md5'
require 'connection_pool'
require 'csv'
require 'json'

REDIS = ConnectionPool.new(size: 5, timeout: 5) do
	puts "creating global redis pool..."
	if !ENV['REDISTOGO_URL'].nil?
		uri = URI.parse(ENV["REDISTOGO_URL"])
		Redis.new(host: uri.host, port: uri.port, password: uri.password)
	else
		Redis.new
	end
end

class WebhookJob
	include Celluloid
	def deliver(key, url)
		begin
			uri = URI(url)
			res = Net::HTTP.post_form(uri, key: key, action: 'updated')
			body = res.body
			puts "delivered webhook for #{key} to #{url}, response: #{body}"
		rescue
			puts "ERROR delivering webhook on #{key} for #{url.inspect}"
		end
	end
end

class App < Sinatra::Base
 
 	configure do
		set :server, 'thin'
		set :sockets, []
				
		set :webhook_pool,  Celluloid::Actor[:webhook_pool]  = WebhookJob.pool(size: 2)

		set :redis_subscriber, Thread.new {			
			if !ENV['REDISTOGO_URL'].nil?
				uri = URI.parse(ENV["REDISTOGO_URL"])
				redis = Redis.new(host: uri.host, port: uri.port, password: uri.password)
			else
				redis = Redis.new
			end
			redis.subscribe("new") do |on|								
				on.message do |channel, key|									
					sockets_for_key = settings.sockets.select{ |ws|
						ws.request['path'].include?(key) # only send relevent updates to clients. this isn't ideal, though.
					}
					puts "about to send #{sockets_for_key.count} updates for #{key}"
					sockets_for_key.each {|ws|
						EM.next_tick { ws.send("pull") }
					}
				end
			end
		}
	end

	get '/' do		
		erb :index
	end

	get '/bookmarklet/app.js' do
		content_type 'text/javascript'
		erb :bookmarklet_code
	end

	get '/bookmarklet/app.css' do
		content_type 'text/css'
		erb :bookmarklet_styles
	end

	post '/api/v1/page' do
		
	end

	get '/favicon.ico' do
		nil
	end

	get '/redis-status' do
		content_type "text/json"
		REDIS.with{ |redis| redis.info.to_json }
	end

	# curl --data "url=server-endpoint-to-POST&key=what-youre-subscribing-to" http://our-app-server/webhook/register
	post '/webhook/register' do		
		url = params['url'] # the URL to deliver the webhook to
		key = params['key'] # the gdoc key that you want updates for
		puts "creating webhook for #{key} to #{url}"
		REDIS.with{ |redis| 
			redis.sadd("webhook:#{key}", url)
			redis.sadd("webhooks", "#{key}")
		}
	end

	get '/ws/:key' do
		if request.websocket?
			request.websocket do |ws|
				ws.onopen do   					
					settings.sockets << ws					
					warn("ws opened | #{params['key']} | client_count: #{settings.sockets.count} (+1)")   					
				end
				ws.onmessage do |message|
					key = ws.request['path'].split('/').last										
					puts "websocket client: #{key} : #{message}"
				end
				ws.onclose do					
					settings.sockets.delete(ws)
					puts "ws closed | client_count: #{settings.sockets.count} (-1)"
				end
			end
		end
	end

end