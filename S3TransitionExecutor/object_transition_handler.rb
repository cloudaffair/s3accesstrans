require 'json'
require 'access_store'
require 'aws-sdk'
require 'aws-sdk-lambda'

def lambda_handler (event:, context:)
  puts "Event Received : #{event}"
  puts "Context Received : #{context}"
  access_store = AccessStore.new
  access_store.update_transition_record(event["_id"], {doc: {transition_state: "inprogress"}})
  bucketName = event["_source"]["bucket"]
  objectKey = event["_source"]["object_key"]
  dest_storage_class = event["_source"]["dest_transition_class"]

  accessKey = ENV['ACCESS_KEY']
  secretKey = ENV['SECRET']

  bucket_region = 'us-east-1'

  #client = Aws::S3::Client.new(:access_key_id => accessKey, :secret_access_key => secretKey)
  client = Aws::S3::Client.new
  begin
    head_resp = client.head_object({
                                       bucket: bucketName,
                                       key: objectKey,
                                   })
  rescue Aws::S3::Errors::NotFound
    puts "Object (#{event["_id"]}) Does not exist!!, Hence Deleting!"
    access_store.delete_transition_record(event["_id"])
    return
  end

  puts "Head Response : #{head_resp.inspect}"
  if head_resp[:storage_class] == dest_storage_class
    puts "No Transition Required!!. Its in Right storage class"
    access_store.update_transition_record(event["_id"], {doc: {transition_state: "completed", storage_class: dest_storage_class}})
  else
    copy_req = {
        bucket: bucketName,
        key: objectKey,
        storage_class: dest_storage_class,
        copy_source: bucketName + '/' + objectKey,
        acl: "public-read"
    }

    copy_req[:server_side_encryption] = head_resp[:server_side_encryption] if head_resp[:server_side_encryption]
    copy_req[:content_type] = head_resp[:content_type] if head_resp[:content_type]
    begin
      resp = client.copy_object(copy_req)
    rescue
      access_store.update_transition_record(event["_id"], {doc: {transition_state: "error"}})
      return
    end

    access_data =
        {
            access_timestamp: Time.now.utc.to_i * 1000,
            bucket: bucketName,
            object_key: objectKey,
            source_storage_class: head_resp[:storage_class],
            bucket_region: bucket_region,
            destination_storage_class: dest_storage_class,
            content_length: head_resp[:content_length]
        }
    access_store.update_transition_record(event["_id"], {doc: {transition_state: "completed", storage_class: dest_storage_class}})
    access_store.insert_access_record(access_data)
  end
end
