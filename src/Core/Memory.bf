using System;

namespace Keel.Core
{
    // Fast linear arena allocator for deterministic allocations during telemetry bursts.
    public class LinearArena
    {
        private uint8* mBuffer;
        private int mCapacity;
        private int mOffset;

        public this(int capacity)
        {
            this.mCapacity = capacity;
            this.mOffset = 0;
            this.mBuffer = (uint8*)Internal.StdMalloc(capacity);
        }

        public ~this()
        {
            if (mBuffer != null)
            {
                Internal.StdFree(mBuffer);
                mBuffer = null;
            }
        }

        public void* Allocate(int size, int alignment = 8)
        {
            int currentPtr = (int)(intptr)mBuffer + mOffset;
            int alignedPtr = (currentPtr + (alignment - 1)) & ~(alignment - 1);
            int newOffset = (alignedPtr - (int)(intptr)mBuffer) + size;

            if (newOffset > mCapacity)
                return null;

            mOffset = newOffset;
            return (void*)(intptr)alignedPtr;
        }

        public void Reset()
        {
            mOffset = 0;
        }

        public int UsedBytes => mOffset;
        public int CapacityBytes => mCapacity;
    }

    // Fixed-size block pool for track states and telemetry envelopes.
    public class FixedBlockPool<T> where T : struct
    {
        private uint8* mStorage;
        private int* mFreeIndices;
        private int mCapacity;
        private int mFreeCount;
        private int mItemSize;

        public this(int capacity)
        {
            this.mCapacity = capacity;
            this.mFreeCount = capacity;
            this.mItemSize = sizeof(T);
            this.mStorage = (uint8*)Internal.StdMalloc(mCapacity * mItemSize);
            this.mFreeIndices = (int*)Internal.StdMalloc(mCapacity * sizeof(int));

            for (int i = 0; i < capacity; i++)
            {
                mFreeIndices[i] = i;
            }
        }

        public ~this()
        {
            if (mStorage != null)
            {
                Internal.StdFree(mStorage);
                mStorage = null;
            }
            if (mFreeIndices != null)
            {
                Internal.StdFree(mFreeIndices);
                mFreeIndices = null;
            }
        }

        public T* Acquire()
        {
            if (mFreeCount == 0)
                return null;

            int index = mFreeIndices[--mFreeCount];
            T* ptr = (T*)(mStorage + (index * mItemSize));
            *ptr = default;
            return ptr;
        }

        public void Release(T* item)
        {
            if (item == null)
                return;

            int byteOffset = (int)((uint8*)item - mStorage);
            int index = byteOffset / mItemSize;

            if (index >= 0 && index < mCapacity && mFreeCount < mCapacity)
            {
                mFreeIndices[mFreeCount++] = index;
            }
        }

        public int Available => mFreeCount;
        public int TotalCapacity => mCapacity;
    }
}
