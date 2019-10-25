require "elasticsearch"

class EsDatastore

  REQUEST_TIMEOUT = 5 # request timeout in seconds for connection
  RETRY_ON_FAILURE = 2 # num of retries after failure

  def initialize(opts = {})
    @servers = ENV['ES_HOSTS'].split(',')
    get_elasticsearch_client
  end

  def insert_access_record(params, uuid)
    execute_query("post", {id: uuid, index: 'object_access', type: 'insert_object_access', body: params})
  end

  def insert_transition_record(params, uuid)
    execute_query("post", {id: uuid, index: 'object_transition', type: 'insert_object_transition', body: params})
  end

  def get_transition_record(objectKey, bucket)
    search_params = {
        "query" => {
            "bool" => {
                "must" => [
                    {"match" => {"object_key" => objectKey }},
                    {"match" => {"bucket" => bucket}}
                ]
            }
        },
        "size" => 1,
        "sort" => {
            "access_timestamp" => {
                "order" => "desc"
            }
        }
    }

    execute_query("get", {index: 'object_transition', type: 'insert_object_transition', body: search_params})
  end

  def update_transition_record(id, params)
    execute_query("update", {index: 'object_transition', type: 'insert_object_transition', id: id, body: params})
  end

  private

  def execute_query (q_type, params)
    response = {}
    begin
      get_elasticsearch_client
      case q_type
        when 'post'
          response = @es_client.create params
        when 'update'
          response = @es_client.update params
        when 'get'
          response = @es_client.search params
      end
    rescue StandardError => e
      puts ("EsDatastore:elasticsearch.failure #{q_type} Could not read/write to datastore: #{e.message}")
      @es_client = nil
      throw e
    end
    response
  end

  def get_elasticsearch_client
    @es_client ||= Elasticsearch::Client.new(
        {hosts: @servers, retry_on_failure: RETRY_ON_FAILURE, request_timeout: REQUEST_TIMEOUT, log: true, send_get_body_as: 'POST'})
  end
end