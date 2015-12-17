#==============================================================================#
# sns.jl
#
# SNS API. See http://aws.amazon.com/documentation/sns/
#
# Copyright Sam O'Connor 2014 - All rights reserved
#==============================================================================#


export sns_delete_topic, sns_create_topic, sns_subscribe_sqs,
       sns_subscribe_email, sns_publish


sns_arn(aws, topic_name) = arn(aws, "sns", topic_name)


sns(aws, query) = do_request(post(aws, "sns", "2010-03-31", query))


function sns(aws, action, topic; args...)

    sns(aws, merge(StrDict(args),
                   "Action" => action,
                   "Name" => topic,
                   "TopicArn" => sns_arn(aws, topic)))
end


function sns_create_topic(aws, topic_name) 

    sns(aws, "CreateTopic", topic_name)
end


function sns_delete_topic(aws, topic_name)

    sns(aws, "DeleteTopic", topic_name)
end


function sns_publish(aws, topic_name, message, subject="No Subject")

    if length(subject) > 100
        subject = subject[1:100]
    end
    sns(aws, "Publish", topic_name, Message = message, Subject = subject)
end


function sns_subscribe_sqs(aws, topic_name, queue; raw=flase)

    r = sns(aws, StrDict("Action" => "Subscribe",
                         "Name" => topic_name,
                         "TopicArn" => sns_arn(aws, topic_name),
                         "Endpoint" => sqs_arn(queue),
                         "Protocol" => "sqs"))

    if raw
        sns(aws, "SetSubscriptionAttributes", topic_name,
                  SubscriptionArn = get(parse_xml(r.data), "SubscriptionArn"),
                  AttributeName = "RawMessageDelivery",
                  AttributeValue = "true")
    end

    sqs(queue, StrDict(
        "Action" => "SetQueueAttributes",
        "Attribute.Name" => "Policy",
        "Attribute.Value" => """{
          "Version": "2008-10-17",
          "Statement": [
            {
              "Effect": "Allow",
              "Principal": {
                "AWS": "*"
              },
              "Action": "SQS:SendMessage",
              "Resource": "$(sqs_arn(queue))",
              "Condition": {
                "ArnEquals": {
                  "aws:SourceArn": "$(sns_arn(aws, topic_name))"
                }
              }
            }
          ]
        }"""
    ))
end


function sns_subscribe_email(aws, topic_name, email)

    sns(aws, topic_name, "Subscribe", Endpoint = email, Protocol = "email")
end



#==============================================================================#
# End of file.
#==============================================================================#
