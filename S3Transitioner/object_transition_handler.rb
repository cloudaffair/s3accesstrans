require 'json'
require 'access_store'
require 'aws-sdk-lambda'

MAX_FILE_SIZE = 1 * 2 ** 30

STORAGE_CLASS_TRANSITION_FLOW = [ "STANDARD_IA", "GLACIER", "DEEP_ARCHIVE" ]

def lambda_handler (event: , context:)
  puts "Event Received : #{event}"
  puts "Context Received : #{context}"
  @accessKey = ENV['ACCESS_KEY']
  @secretKey = ENV['SECRET']
  @transition_rule = ENV['TRANSITION_RULE']
  @transition_rule = JSON.parse(@transition_rule)
  puts "Transition Rule : #{@transition_rule}"
  #@lambda_client = Aws::Lambda::Client.new(:access_key_id => @accessKey, :secret_access_key => @secretKey)
  @lambda_client = Aws::Lambda::Client.new
  @query = {
      :query => {
          :bool => {
              :must => [
                  {
                      :range => {
                          :access_timestamp => {

                          }
                      }
                  }
              ],
              :must_not => [

              ]
          }
      },
      :sort => {
          :access_timestamp => {
              :order => "asc"
          }
      },
      :size => 100
  }

  process_class = STORAGE_CLASS_TRANSITION_FLOW
  STORAGE_CLASS_TRANSITION_FLOW.each do | transition_class |
    unless (@transition_rule[transition_class].nil?)
      process_class = process_class - [transition_class]
      puts process_class.to_s
      start_r, end_r = get_range(transition_class, process_class, @transition_rule)
      puts "#{transition_class} => #{start_r} : #{end_r}"
      initiate_transition(transition_class, start_r, end_r)
    end
  end
end

def initiate_transition(transition_class, start_r, end_r)
  if (end_r != -1 )
    range = {
        # changing to mins for now
        :lt => "now-#{start_r}m",
        :gt => "now-#{end_r}m"
    }
  else
    range = {
        :lt => "now-#{start_r}m"
    }
  end
  @query[:query][:bool][:must][0][:range][:access_timestamp] = range
  exclude = [
      {
          :match => {
              :storage_class => transition_class
          }
      },
      {
          :match => {
              :transition_state => "inprogress"
          }
      }
  ]
  @query[:query][:bool][:must_not] = exclude
  puts @query.to_json
  access_store = AccessStore.new
  listobjs =  access_store.query_transition_records(@query.to_json)
  listobjs["hits"]["hits"].each do |transition_record |
    transition_record["_source"]["dest_transition_class"] = transition_class
    @lambda_client.invoke({
         :function_name => "s3transitionexecutor",
         :invocation_type => "Event",
         :log_type => "None",
         :client_context => "S3Transitioner",
         :payload => transition_record.to_json
     })
  end
end

def get_range(transition_class, transitionlist, transition_rule)
  start_r = transition_rule[transition_class]
  end_r = -1
  transitionlist.each do |next_transition|
    unless transition_rule[next_transition].nil?
      end_r = transition_rule[next_transition]
      break
    end
  end
  puts "Start_r #{start_r} : end_r #{end_r}"
  return start_r, end_r
end
