TARGET = libInject.dylib
SRCS = AccountManager.m FloatWindow.m InjectMain.m DeviceFaker.m FakerConfig.m
SDK = $(shell xcrun --sdk iphoneos --show-sdk-path)
CC = $(shell xcrun --sdk iphoneos --find clang)
CFLAGS = -arch arm64 -isysroot $(SDK) -mios-version-min=12.0 -fobjc-arc -O2
LDFLAGS = -dynamiclib -arch arm64 -isysroot $(SDK) -mios-version-min=12.0 \
          -framework UIKit -framework Foundation -framework CoreGraphics \
          -framework AdSupport -framework CommonCrypto -lobjc

OBJS = $(SRCS:.m=.o)

$(TARGET): $(OBJS)
	$(CC) $(LDFLAGS) -o $@ $^

%.o: %.m
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -f $(OBJS) $(TARGET)