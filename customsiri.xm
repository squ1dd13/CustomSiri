@interface AceObject : NSObject
@property(copy, nonatomic) NSString *refId;
@property(copy, nonatomic) NSString *aceId;
- (id)properties;
- (id)dictionary;
+ (id)aceObjectWithDictionary:(id)arg1 context:(id)arg2;
@end

@interface AFConnection : NSObject
@property (nonatomic, copy) NSString *userSpeech;
@end

static NSDictionary *customReplies;

#pragma mark Getting User Speech
%hook AFConnectionClientServiceDelegate
-(void)speechRecognized:(id)arg1 {
	#define arg1 (NSObject *)arg1
	//arg1 --> recognition --> phrases --> object --> interpretations --> object --> tokens --> object --> text
	NSMutableString *fullPhrase = [NSMutableString string];
	NSArray *phrases = [arg1 valueForKeyPath:@"recognition.phrases"];
	if([phrases count] > 0) {
		for(id phrase in phrases) {
			NSArray *interpretations = [(NSObject *)phrase valueForKey:@"interpretations"];
			if([interpretations count] > 0) {
				id interpretation = interpretations[0];
				NSArray *tokens = [(NSObject *)interpretation valueForKey:@"tokens"];
				if([tokens count] > 0) {
					for(id token in tokens) {
						NSLog(@"%@", [(NSObject *)token valueForKey:@"text"]);
						[fullPhrase appendString:[[(NSObject *)token valueForKey:@"text"] stringByAppendingString:@" "]];
					}
				}
			}
		}
	}
	#undef arg1
	NSString *speech = [[[fullPhrase copy] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] lowercaseString];
	[[self valueForKey:@"_connection"] setValue:speech forKey:@"userSpeech"];
	%orig;
}
%end

#pragma mark Custom reply
%hook AFConnection
%property (nonatomic, copy) NSString *userSpeech;

-(void)_doCommand:(id)arg1 reply:(/*^block*/id)arg2 {
	//work out if we should be giving a custom reply
	NSString *stringToSpeak = @"rreeeeeee";

	//of course, in a real project this would be from a file or something loaded in the constructor
	customReplies = @{
		@"welcome" : @"To Jurassic Park."
	};

	if(customReplies[self.userSpeech]) {
		stringToSpeak = customReplies[self.userSpeech];
	} else {
		//say the original and quit
		%orig;
		return;
	}

	//create a context for the ace object
	id context = NSClassFromString(@"BasicAceContext");
	id object = arg1;

	//get the original dictionary
	NSMutableDictionary *dict = [[(NSObject *)object valueForKey:@"dictionary"] mutableCopy];

	/*
	How it works:
	Siri processes what the user says to it, and then cooks up a reply. It then synthesizes the speech for the reply, while displaying a view with the spoken text.
	To give custom replies, we need to a) change the string that is synthesized, and b) change the text of the view.
	*/

	//change the text on the views
	if([dict objectForKey:@"views"]) {
		NSArray *views = [dict objectForKey:@"views"];
		NSMutableArray *modifiedViews = [NSMutableArray array];

		//views is an array of dictionaries
		for(NSDictionary *view in views) {
			NSMutableDictionary *mutableView = [view mutableCopy];
			[mutableView setValue:stringToSpeak forKey:@"speakableText"];
			[mutableView setValue:stringToSpeak forKey:@"text"];
			[modifiedViews addObject:[mutableView copy]];
		}

		[dict setValue:[modifiedViews copy] forKey:@"views"];
	}

	//change the speech string
	if([dict objectForKey:@"dialogStrings"]) {
		[dict setValue:@[stringToSpeak] forKey:@"dialogStrings"];
	}

	//create a new ace object with the modified dictionary
	AceObject *aceObject = [%c(AceObject) aceObjectWithDictionary:[dict copy] context:context];

	//run normally with the modified ace object and the original block
	%orig(aceObject, arg2);

	//reset
	self.userSpeech = @"";
}
%end
