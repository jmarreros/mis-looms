<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;

class TokenController extends Controller
{
    private const NOMBRE = 'apps';

    public function show(Request $request)
    {
        return view('admin.token', [
            'tokens' => $request->user()->tokens()->where('name', self::NOMBRE)->latest()->get(),
        ]);
    }

    /** Revoca los tokens anteriores y crea uno nuevo; el valor solo se muestra una vez. */
    public function regenerar(Request $request): RedirectResponse
    {
        $request->user()->tokens()->where('name', self::NOMBRE)->delete();
        $nuevo = $request->user()->createToken(self::NOMBRE);

        return redirect()->route('admin.token')->with('token_nuevo', $nuevo->plainTextToken);
    }
}
