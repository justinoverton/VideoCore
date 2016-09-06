/*
 
 Video Core
 Copyright (c) 2014 Oleksa Korin
 
 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:
 
 The above copyright notice and this permission notice shall be included in
 all copies or substantial portions of the Software.
 
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 THE SOFTWARE.
 
 */

#ifndef CaptureSessionSource_hpp
#define CaptureSessionSource_hpp

#include <videocore/sources/ISource.hpp>
#include <videocore/transforms/IOutput.hpp>
#import <AVFoundation/AVfoundation.h>
#import <videocore/sources/iOS/VCWriter.h>

namespace videocore { namespace iOS {
    
    /*!
     *  Capture data from the capture session.
     */
    class CaptureSessionSource : public ISource, public std::enable_shared_from_this<CaptureSessionSource>
    {
    public:
        /*!
         *  Returns a serial dispatch queue to be used for capture session. 
         *  All children are enforced to have the same dispatch queue.
         */
        static dispatch_queue_t sharedDispatchQueue();
        
        /*!
         *  Returns a capture session to be used in all children.
         *  All children are enforced to have the same capture session.
         */
        static AVCaptureSession *sharedCaptureSession();
        
        /*! Constructor */
        CaptureSessionSource();
        
        /*! Destructor */
        virtual ~CaptureSessionSource();
        
        /*! ISource::setOutput */
        void setOutput(std::shared_ptr<IOutput> output);
        
        /*! Property for capture output delegate */
        VCWriter *writer();
        void setWriter(VCWriter *writer);
        
        /*!
         *  Setup camera properties
         *
         *  \param session  Capture session to use, internal one is initialized, if parameter is nil
         */
        virtual void setup();
        
    public:
        /*! Used by Objective-C Capture Session */
        void bufferCaptured(CMSampleBufferRef sampleBuffer);
        
    protected:
        /*!
         *  Method to create and setup capture session connections from inputs to outputs
         */
        virtual void setupCaptureSessionConnections() = 0;
        
        /*!
         *  Returns media type for the source
         */
        virtual NSString *mediaType() = 0;
        
        /*!
         *  Get capture devices for current media type
         */
        NSArray *getCaptureDevices();
        
        /*!
         *  Adds capture input.
         *
         *  \param input    Input to add
         *
         *  \return         Success. 'true', if input was added.
         */
        bool addCaptureInput(AVCaptureInput *input);
        
        /*!
         *  Removes capture input.
         *
         *  \param input    Input to remove
         */
        void removeCaptureInput(AVCaptureInput *input);
        
        /*!
         *  Universal setter for ObjC objects
         */
        void setValueForField(id *field, id value);
        
        /*!
         *  Property for capture input
         */
        id m_captureInput;
        virtual id captureInput();
        virtual void setCaptureInput(id value);
        
        /*!
         *  Property for capture output
         */
        id m_captureOutput;
        virtual id captureOutput();
        virtual void setCaptureOutput(id value);
        
        /*!
         *  Property for capture output delegate
         */
        id m_captureOutputDelegate;
        virtual id captureOutputDelegate();
        virtual void setCaptureOutputDelegate(id value);
        
        /*!
         *  Removes capture outputs and inputs from session
         */
        virtual void removeSessionConnections();
        
        /*!
         *  Property for capture session
         */
        AVCaptureSession *m_captureSession;
        virtual AVCaptureSession *captureSession();
        virtual void setCaptureSession(AVCaptureSession *session);
        
        std::weak_ptr<IOutput> m_output;
        
        VCWriter *m_writer;
    };
    
}
}

#endif /* CaptureSessionSource_hpp */
