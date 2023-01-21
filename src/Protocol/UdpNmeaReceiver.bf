using System;
using System.IO;
using System.Net;
using System.Net.Sockets;
using Keel.Core;

namespace Keel.Protocol
{
    // High-throughput UDP datagram listener for receiving raw NMEA 0183 AIS telemetry feeds.
    public class UdpNmeaReceiver
    {
        private Socket mSocket;
        private int mPort;
        private bool mRunning;
        private uint8[2048] mRecvBuffer;

        public this(int port = 10110)
        {
            this.mPort = port;
            this.mRunning = false;
            this.mSocket = null;
        }

        public ~this()
        {
            Stop();
        }

        public bool Start()
        {
            if (mRunning)
                return true;

            mSocket = new Socket(.IPv4, .Dgram, .UDP);
            mSocket.Blocking = false;

            var endpoint = scope IPEndPoint(IPAddress.Any, (uint16)mPort);
            if (mSocket.Bind(endpoint) case .Err)
            {
                delete mSocket;
                mSocket = null;
                return false;
            }

            mRunning = true;
            return true;
        }

        public void Stop()
        {
            if (mRunning)
            {
                mRunning = false;
                if (mSocket != null)
                {
                    mSocket.Close();
                    delete mSocket;
                    mSocket = null;
                }
            }
        }

        // Polls the non-blocking UDP socket and returns true if a datagram was received into outSentence.
        public bool Poll(String outSentence)
        {
            outSentence.Clear();
            if (!mRunning || mSocket == null)
                return false;

            EndPoint senderEp = scope IPEndPoint(IPAddress.Any, 0);
            var res = mSocket.ReceiveFrom(Span<uint8>(&mRecvBuffer[0], mRecvBuffer.Count), ref senderEp);

            if (res case .Ok(let bytesRead))
            {
                if (bytesRead > 0)
                {
                    for (int i = 0; i < bytesRead; i++)
                    {
                        char8 c = (char8)mRecvBuffer[i];
                        if (c == '\r' || c == '\n')
                            break;
                        outSentence.Append(c);
                    }
                    return outSentence.Length > 0;
                }
            }

            return false;
        }

        public bool IsRunning => mRunning;
        public int Port => mPort;
    }
}
