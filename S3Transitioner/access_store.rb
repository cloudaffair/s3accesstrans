require 'elasticsearch'

class AccessStore
  REQUEST_TIMEOUT = 5 # request timeout in seconds for connection
  RETRY_ON_FAILURE = 2 # num of retries after failure

  def initialize(opts = {})
    @servers = ENV['ES_HOSTS'].split(',')
    get_elasticsearch_client
  end

  def insert_access_record(params)
    uuid = nil
    begin
      uuid = generate_uid(params[:object_key], params[:bucket], Time.now.utc.to_i.to_s)
    rescue StandardError => e
      @logger.error("EsDatastore:UUID generate error #{e.message}")
      throw e
    end

    execute_query("post", {id: uuid, index: 'object_access', type: 'insert_object_access', body: params})
  end

  def query_transition_records(query)
    @es_client.search index: 'object_transition', body: query
  end

  def insert_transition_record(params)
    uuid = nil
    begin
      uuid = generate_uid(params[:object_key], params[:bucket])
    rescue StandardError => e
      @logger.error("EsDatastore:UUID generate error #{e.message}")
      throw e
    end

    execute_query("post", {id: uuid, index: 'object_transition', type: 'insert_object_transition', body: params})
  end

  def delete_transition_record(id)
    execute_query("delete", {index: 'object_transition', type: 'insert_object_transition', id: id})
  end
  def get_transition_record(params)
    execute_query("get", {index: 'object_transition', type: 'insert_object_transition', body: params})
  end

  def update_transition_record(id, params)
    execute_query("update", {index: 'object_transition', type: 'insert_object_transition', id: id, body: params})
  end


  def execute_query (q_type, params)
    response = {}
    begin
      get_elasticsearch_client
      case q_type
        when 'post'
          response = @es_client.create params
        when 'update'
          response = @es_client.update index: params[:index], type: params[:type], id: params[:id],
                                       body: params[:body]

        when 'get'
          response = @es_client.search index: params[:index], type: params[:type],
                                       body: {
                                           "query" => {
                                               "bool" => {
                                                   "must" => [
                                                       {"match" => {"object_key" => params[:body][:object_key]}},
                                                       {"match" => {"bucket" => params[:body][:bucket]}}
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
        when 'delete'
          response = @es_client.delete index: params[:index], type: params[:type], id: params[:id]
      end
    rescue StandardError => e
      puts ("EsDatastore:elasticsearch.failure #{q_type} Could not read/write to datastore: #{e.message}")
      @es_client = nil
      throw e
    end
    response
  end

  def generate_uid(object_key, bucket, time = nil)
    if time.nil?
      Digest::MD5.hexdigest(bucket + object_key)
    else
      Digest::MD5.hexdigest(time + bucket + object_key)
    end
  end

  def get_elasticsearch_client
    @es_client ||= Elasticsearch::Client.new(
        {hosts: @servers, retry_on_failure: RETRY_ON_FAILURE, request_timeout: REQUEST_TIMEOUT, log: true, send_get_body_as: 'POST'})
  end
end