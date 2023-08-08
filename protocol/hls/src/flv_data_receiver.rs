use {
    super::{
        errors::{HlsError, HlsErrorValue},
        flv2hls::Flv2HlsRemuxer,
    },
    rtmp::session::errors::{SessionError, SessionErrorValue},
    std::time::Duration,
    streamhub::{
        define::{
            FrameData, FrameDataReceiver, NotifyInfo, StreamHubEvent, StreamHubEventSender,
            SubscribeType, SubscriberInfo,
        },
        stream::StreamIdentifier,
        utils::{RandomDigitCount, Uuid},
    },
    tokio::{sync::mpsc, time::sleep},
    xflv::define::FlvData,
};

////https://www.jianshu.com/p/d6311f03b81f

pub struct FlvDataReceiver {
    app_name: String,
    stream_name: String,
    event_producer: StreamHubEventSender,
    data_consumer: FrameDataReceiver,
    media_processor: Flv2HlsRemuxer,
    subscriber_id: Uuid,
}

impl FlvDataReceiver {
    pub fn new(
        app_name: String,
        stream_name: String,
        event_producer: StreamHubEventSender,
        duration: i64,
        need_record: bool,
    ) -> Self {
        let (_, data_consumer) = mpsc::unbounded_channel();
        let subscriber_id = Uuid::new(RandomDigitCount::Four);

        Self {
            app_name: app_name.clone(),
            stream_name: stream_name.clone(),
            data_consumer,
            event_producer,
            media_processor: Flv2HlsRemuxer::new(duration, app_name, stream_name, need_record),
            subscriber_id,
        }
    }

    pub async fn run(&mut self) -> Result<(), HlsError> {
        self.subscribe_from_rtmp_channels(self.app_name.clone(), self.stream_name.clone())
            .await?;
        self.receive_flv_data().await?;

        Ok(())
    }

    pub async fn receive_flv_data(&mut self) -> Result<(), HlsError> {
        let mut retry_count = 0;

        loop {
            if let Some(data) = self.data_consumer.recv().await {
                let flv_data: FlvData = match data {
                    FrameData::Audio { timestamp, data } => FlvData::Audio { timestamp, data },
                    FrameData::Video { timestamp, data } => FlvData::Video { timestamp, data },
                    _ => continue,
                };
                retry_count = 0;
                self.media_processor.process_flv_data(flv_data)?;
            } else {
                sleep(Duration::from_millis(100)).await;
                retry_count += 1;
            }
            //When rtmp stream is interupted here we retry 10 times.
            //maybe have a better way to judge the stream status.
            //will do an optimization in the future.
            //todo
            if retry_count > 10 {
                break;
            }
        }

        self.media_processor.clear_files()?;
        self.unsubscribe_from_rtmp_channels().await
    }

    pub fn flush_response_data(&mut self) -> Result<(), HlsError> {
        Ok(())
    }

    pub async fn subscribe_from_rtmp_channels(
        &mut self,
        app_name: String,
        stream_name: String,
    ) -> Result<(), HlsError> {
        let (sender, receiver) = mpsc::unbounded_channel();
        /*the sub info is only used to transfer from RTMP to HLS, but not for client player */
        let sub_info = SubscriberInfo {
            id: self.subscriber_id,
            sub_type: SubscribeType::GenerateHls,
            notify_info: NotifyInfo {
                request_url: String::from(""),
                remote_addr: String::from(""),
            },
        };

        let identifier = StreamIdentifier::Rtmp {
            app_name,
            stream_name,
        };

        let subscribe_event = StreamHubEvent::Subscribe {
            identifier,
            info: sub_info,
            sender,
        };

        let rv = self.event_producer.send(subscribe_event);
        if rv.is_err() {
            let session_error = SessionError {
                value: SessionErrorValue::StreamHubEventSendErr,
            };
            return Err(HlsError {
                value: HlsErrorValue::SessionError(session_error),
            });
        }

        self.data_consumer = receiver;

        Ok(())
    }

    pub async fn unsubscribe_from_rtmp_channels(&mut self) -> Result<(), HlsError> {
        let sub_info = SubscriberInfo {
            id: self.subscriber_id,
            sub_type: SubscribeType::PlayerHls,
            notify_info: NotifyInfo {
                request_url: String::from(""),
                remote_addr: String::from(""),
            },
        };

        let identifier = StreamIdentifier::Rtmp {
            app_name: self.app_name.clone(),
            stream_name: self.stream_name.clone(),
        };

        let subscribe_event = StreamHubEvent::UnSubscribe {
            identifier,
            info: sub_info,
        };
        if let Err(err) = self.event_producer.send(subscribe_event) {
            log::error!("unsubscribe_from_channels err {}\n", err);
        }

        Ok(())
    }
}
