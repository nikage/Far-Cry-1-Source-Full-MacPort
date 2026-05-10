#import "CryMetalGameView.h"

@implementation CryMetalGameView

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self)
        self.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    return self;
}

- (BOOL)acceptsFirstResponder
{
    return YES;
}

- (void)keyDown:(NSEvent *)event
{
}

- (void)keyUp:(NSEvent *)event
{
}

- (void)flagsChanged:(NSEvent *)event
{
}

- (BOOL)performKeyEquivalent:(NSEvent *)event
{
    return YES;
}

@end
