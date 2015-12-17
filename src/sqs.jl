#==============================================================================#
# sqs.jl
#
# SQS API. See http://aws.amazon.com/documentation/sqs/
#
# Copyright Sam O'Connor 2014 - All rights reserved
#==============================================================================#


export sqs_get_queue, sqs_create_queue, sqs_delete_queue, 
       sqs_send_message, sqs_send_message_batch, sqs_receive_message,
       sqs_delete_message, sqs_flush, sqs_get_queue_attributes, sqs_count,
       sqs_busy_count


# SQS Queue Lookup.
# Find queue URL.
# Return a revised "aws" dict that captures the URL path.

function sqs_get_queue(aws, name)

    @safe try

        r = sqs(aws, Action="GetQueueUrl", QueueName = name)

        url = get(parse_xml(r.data), "GetQueueUrlResult")
        return merge(aws, resource = URI(url).path)

    catch e
        @trap e if e.code == "AWS.SimpleQueueService.NonExistentQueue"
            return nothing
        end
    end
end


sqs_name(q) = split(q[:resource], "/")[3]
sqs_arn(q) = arn(q, "sqs", sqs_name(q))


# Create new queue with "name".
# options: VisibilityTimeout, MessageRetentionPeriod, DelaySeconds etc
# See http://docs.aws.amazon.com/AWSSimpleQueueService/latest/APIReference/API_CreateQueue.html

function sqs_create_queue(aws, name; options...)

    println("""Creating SQS Queue "$name"...""")

    query = StrDict(
        "Action" => "CreateQueue",
        "QueueName" => name
    )
    
    for (i, (k, v)) in enumerate(options)
        query["Attribute.$i.Name"] = k
        query["Attribute.$i.Value"] = v
    end

    @max_attempts 4 try

        r = sqs(aws, query)
        url = get(parse_xml(r.data), "QueueUrl")
        return merge(aws, resource = URI(url).path)

    catch e

        if typeof(e) == AWSException

            if (e.code == "QueueAlreadyExists")
                sqs_delete_queue(aws, name)
                @retry
            end

            if (e.code == "AWS.SimpleQueueService.QueueDeletedRecently")
                println("""Waiting 1 minute to re-create Queue "$name"...""")
                sleep(60)
                @retry
            end
        end
    end

    assert(false) # Unreachable.
end


function sqs_delete_queue(queue)

    @safe try

        println("Deleting SQS Queue $(aws["path"])")
        sqs(aws, Action="DeleteQueue")

    catch e
        @trap e if e.code == "AWS.SimpleQueueService.NonExistentQueue" end
    end
end


function sqs_send_message(queue, message)

    sqs(queue, Action="SendMessage",
               MessageBody = message,
               MD5OfMessageBody = string(digest("md5", message)))
end


function sqs_send_message_batch(queue, messages)

    batch = Dict()
    
    for (i, message) in enumerate(messages)
        batch["SendMessageBatchRequestEntry.$i.Id"] = i
        batch["SendMessageBatchRequestEntry.$i.MessageBody"] = message
    end
    sqs(queue, Action="SendMessageBatch", Attributes=batch)
end


function sqs_receive_message(queue)

    r = sqs(queue, Action="ReceiveMessage", MaxNumberOfMessages = "1")
    xdoc = parse_xml(r.data)

    handle = get(xdoc, "ReceiptHandle")
    if handle == ""
        return nothing
    end

    message = get(xdoc, "Body")
    @assert get(xdoc, "MD5OfBody") == hexdigest("md5", message)

    @symdict(message, handle)
end
    

function sqs_delete_message(queue, message)

    sqs(queue, Action="DeleteMessage", ReceiptHandle = message[:handle])
end


function sqs_flush(queue)

    while (m = sqs_receive_message(queue)) != nothing
        sqs_delete_message(queue, m)
    end
end


function sqs_get_queue_attributes(queue)

    @safe try

        r = sqs(queue, StrDict("Action" => "GetQueueAttributes",
                               "AttributeName.1" => "All"))

        return dict(parse_xml(r.data), "GetQueueAttributesResult", "Attribute")

    catch e
        @trap e if e.code == "AWS.SimpleQueueService.NonExistentQueue"
            return nothing
        end
    end
end


function sqs_count(queue)
    
    parse(Int,sqs_get_queue_attributes(queue)["ApproximateNumberOfMessages"])
end


function sqs_busy_count(queue)
    
    parase(Int,sqs_get_queue_attributes(queue)["ApproximateNumberOfMessagesNotVisible"])
end



#==============================================================================#
# End of file.
#==============================================================================#
