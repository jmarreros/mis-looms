<?php

namespace App\Mail;

use App\Models\Video;
use App\Models\Vista;
use Illuminate\Mail\Mailable;
use Illuminate\Mail\Mailables\Content;
use Illuminate\Mail\Mailables\Envelope;

class PrimeraVisita extends Mailable
{
    public function __construct(public Video $video, public Vista $vista) {}

    public function envelope(): Envelope
    {
        return new Envelope(subject: 'Han visto tu video: '.$this->video->titulo());
    }

    public function content(): Content
    {
        return new Content(view: 'correo.primera-visita');
    }
}
