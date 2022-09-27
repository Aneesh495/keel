using System;
using System.Threading;

namespace Keel.Core
{
    // High-throughput lock-free Single-Producer Single-Consumer (SPSC) ring buffer.
    public class SpscRingBuffer<T> where T : struct
    {
        private T[] mBuffer;
        private int mCapacity;
        private int mMask;

        // Cache-line aligned head and tail indices
        private int64 mHead; // consumer index
        private int64 mTail; // producer index

        public this(int capacityPow2)
        {
            // Ensure capacity is a power of two
            int cap = 1;
            while (cap < capacityPow2)
                cap <<= 1;

            this.mCapacity = cap;
            this.mMask = cap - 1;
            this.mBuffer = new T[mCapacity];
            this.mHead = 0;
            this.mTail = 0;
        }

        public ~this()
        {
            delete mBuffer;
        }

        // Tries to enqueue an item. Returns false if the buffer is full.
        public bool TryEnqueue(in T item)
        {
            int64 currentTail = Interlocked.Read(ref mTail);
            int64 currentHead = Interlocked.Read(ref mHead);

            if ((currentTail - currentHead) >= mCapacity)
            {
                return false; // Buffer full
            }

            int index = (int)(currentTail & mMask);
            mBuffer[index] = item;

            // Memory barrier release semantics
            Interlocked.Exchange(ref mTail, currentTail + 1);
            return true;
        }

        // Tries to dequeue an item into outItem. Returns false if buffer is empty.
        public bool TryDequeue(out T outItem)
        {
            int64 currentHead = Interlocked.Read(ref mHead);
            int64 currentTail = Interlocked.Read(ref mTail);

            if (currentHead >= currentTail)
            {
                outItem = default;
                return false; // Buffer empty
            }

            int index = (int)(currentHead & mMask);
            outItem = mBuffer[index];

            // Memory barrier acquire semantics
            Interlocked.Exchange(ref mHead, currentHead + 1);
            return true;
        }

        public int Count
        {
            get
            {
                int64 diff = Interlocked.Read(ref mTail) - Interlocked.Read(ref mHead);
                return (int)Math.Max(0, diff);
            }
        }

        public bool IsEmpty => Interlocked.Read(ref mHead) >= Interlocked.Read(ref mTail);
        public bool IsFull => (Interlocked.Read(ref mTail) - Interlocked.Read(ref mHead)) >= mCapacity;
        public int Capacity => mCapacity;
    }
}
