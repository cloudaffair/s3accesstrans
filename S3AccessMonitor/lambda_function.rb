require 'json'
require "aws-sdk"
require 'elastic_datastore'
require "geocoder"

def lambda_handler(event:, context:)

  puts "Event received: #{event}"

  bucketName = event["detail"]["requestParameters"]["bucketName"]
  objectKey = event["detail"]["requestParameters"]["key"]
  userAgent = event["detail"]["userAgent"]
  sourceIp = event["detail"]["sourceIPAddress"]
  eventName = event["detail"]["eventName"]

  puts "bucketName: #{bucketName}"
  puts "object key: #{objectKey}"
  puts "user agent: #{userAgent}"
  puts "source Ip: #{sourceIp}"
  puts "Event name: #{eventName}"

  client = Aws::S3::Client.new
  head_resp = client.head_object({
                                     bucket: bucketName,
                                     key: objectKey,
                                 })

  puts "Head Object response #{head_resp}"

  location_resp = client.get_bucket_location(bucket: bucketName)
  bucket_region = 'us-east-1'
  unless location_resp.nil?
    bucket_region = location_resp[:location_constraint] unless location_resp[:location_constraint].empty?
  end

  from_storage_class = head_resp[:storage_class] ? head_resp[:storage_class] : "STANDARD"
  content_length = head_resp[:content_length]
  puts "Storage Class for object #{objectKey} : #{from_storage_class}"

  # Move the object to STANDARD storage class since it is accessed from non-CF user agents
  if eventName == "GetObject" && from_storage_class != "STANDARD" && !userAgent.include?('CloudFront')
    copy_req = {
        bucket: bucketName,
        key: objectKey,
        storage_class: "STANDARD",
        copy_source: bucketName + '/' + objectKey,
        acl: "public-read"
    }

    copy_req[:server_side_encryption] = head_resp[:server_side_encryption] if head_resp[:server_side_encryption]
    copy_req[:content_type] = head_resp[:content_type] if head_resp[:content_type]

    resp = client.copy_object(copy_req)
    to_storage_class = "STANDARD"
  end
  insert_to_es(objectKey, bucketName, from_storage_class, to_storage_class, bucket_region, sourceIp, eventName, userAgent, content_length)
end

def insert_to_es(objectKey, bucket, from_storage_class, to_storage_class, bucket_region, sourceIp, eventName, userAgent, content_length)

  es_client = EsDatastore.new
  uuid = nil

  geo_search = Geocoder.search(sourceIp) unless sourceIp.nil?
  puts "Geo search result #{geo_search}"

  # {"ip"=>"35.162.63.246", "city"=>"Portland", "region"=>"Oregon", "country"=>"US", "loc"=>"45.5235,-122.6762", "postal"=>"97294", "readme"=>"https://ipinfo.io/missingauth"}
  geo_result = geo_search.first unless geo_search.nil?
  location_data = geo_result ? {
      city_name: geo_result.city,
      region_name: geo_result.state,
      country_name: geo_result.country,
      location: geo_result.coordinates.reverse,
      country_code2: geo_result.country_code,
      ip: sourceIp
  } : nil

  userAgent = {
      device: userAgent
  }

  access_data =
      {
          access_timestamp: Time.now.utc.to_i * 1000,
          bucket: bucket,
          object_key: objectKey,
          source_storage_class: from_storage_class,
          bucket_region: bucket_region,
          geoip: location_data,
          useragent: userAgent,
          content_length: content_length,
      }
  if to_storage_class
    access_data[:destination_storage_class] = to_storage_class
    object_copied = true
  end

  es_record = es_client.get_transition_record(objectKey, bucket)
  last_record = es_record["hits"]["hits"][0] rescue nil
  es_record_id = last_record["_id"] unless last_record.nil?

  if es_record_id
    if eventName == 'GetObject'
      # Update access timestamp for Get access only, for PUT & CompleteMultipartUpload only the initial record will suffice !
      puts "Existing record found for the object key #{objectKey}; update the access timestamp"
      if object_copied
        puts "Found object key #{objectKey} copied to another storage; update the storage class & access timestamp"
        es_client.update_transition_record(es_record_id, {doc: {storage_class: to_storage_class, access_timestamp: Time.now.utc.to_i * 1000}})
      else
        es_client.update_transition_record(es_record_id, {doc: {access_timestamp: Time.now.utc.to_i * 1000}})
      end
      access_data[:record_type] = "ACCESS"
    else
      puts "Existing record found for the object key #{objectKey}; with ID #{es_record_id}; do nothing"
      access_data[:record_type] = "COPY"
    end
  else
    puts "Existing record not found for the object key #{objectKey}; insert a new record"
    access_data[:record_type] = "CREATE"
    transition_data =
        {
            access_timestamp: Time.now.utc.to_i * 1000,
            bucket: bucket,
            object_key: objectKey,
            bucket_region: bucket_region,
        }
    transition_data[:storage_class] = to_storage_class.nil? ? from_storage_class : to_storage_class

    puts "ES transition record #{transition_data}"
    uuid = generate_uid(objectKey, bucket)
    es_client.insert_transition_record(transition_data, uuid)
  end

  # Insert an access record !
  puts "ES Access Data #{access_data}"
  uuid = generate_uid(objectKey, bucket, Time.now.utc.to_i.to_s)
  es_client.insert_access_record(access_data, uuid)

end

def generate_uid(object_key, bucket, time = nil)
  if time.nil?
    Digest::MD5.hexdigest(bucket + object_key)
  else
    Digest::MD5.hexdigest(time + bucket + object_key)
  end
end